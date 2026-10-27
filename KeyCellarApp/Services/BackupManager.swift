import AppKit
import KeyCellarCore
import Foundation
import Observation
import UniformTypeIdentifiers

/// Export, import and scheduled backups of the whole vault.
///
/// Scheduled backups run only right after a successful unlock: that is the
/// one moment the enclave's authentication is fresh, so the export needs no
/// extra Touch ID and never surprises the user with a prompt mid-work. The
/// passphrase for them lives in memory from the moment it is entered until
/// the vault locks.
@MainActor
@Observable
final class BackupManager {
    enum Schedule: String, CaseIterable {
        case off, daily, weekly

        var interval: TimeInterval? {
            switch self {
            case .off: nil
            case .daily: 86_400
            case .weekly: 7 * 86_400
            }
        }
    }

    static let keepChoices = [3, 5, 10, 20]
    static let staleAfterDays = 7
    nonisolated static let filePrefix = "DKB Secret Backup "
    nonisolated static let fileExtension = "dkbsecret"
    /// Declared in Info.plist (`UTExportedTypeDeclarations`).
    static let fileType = UTType(exportedAs: "com.dangkhoabach.dkb-secret.backup")

    var schedule: Schedule { didSet { try? settings.set(Keys.schedule, schedule.rawValue) } }
    var keepCount: Int { didSet { try? settings.set(Keys.keep, String(keepCount)) } }
    private(set) var lastBackupAt: Date?
    private(set) var folderName: String?
    private(set) var lastMessage: String?
    private(set) var lastError: String?
    /// The scheduled backups' passphrase for this unlocked session.
    private(set) var hasSessionPassphrase = false
    private var sessionPassphrase: SecretBytes?

    private let vault: SecretVault
    private let settings: SettingsRepository

    enum Keys {
        static let schedule = "backup.schedule"
        static let keep = "backup.keep"
        static let lastAt = "backup.lastAt"
        static let folderBookmark = "backup.folderBookmark"
    }

    init(vault: SecretVault, settings: SettingsRepository) {
        self.vault = vault
        self.settings = settings
        schedule = (try? settings.get(Keys.schedule)).flatMap(Schedule.init(rawValue:)) ?? .off
        let keep = (try? settings.get(Keys.keep)).flatMap(Int.init) ?? 5
        keepCount = Self.keepChoices.contains(keep) ? keep : 5
        lastBackupAt = (try? settings.get(Keys.lastAt)).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        folderName = resolveFolder()?.url.lastPathComponent
    }

    var daysSinceLastBackup: Int? {
        lastBackupAt.map { Calendar.current.dateComponents([.day], from: $0, to: .now).day ?? 0 }
    }

    /// True when a scheduled or manual backup is overdue enough to warn about.
    var isStale: Bool {
        guard let days = daysSinceLastBackup else { return true }
        return days >= Self.staleAfterDays
    }

    // MARK: Manual export / import

    func exportNow(passphrase: String) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.fileName(for: Date())
        panel.allowedContentTypes = [Self.fileType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try await VaultBackup.export(vault: vault, passphrase: passphrase)
            try data.write(to: url, options: .atomic)
            recordBackup(Date())
            let count = try BackupCrypto.readHeader(data).itemCount
            lastMessage = String(localized: "Exported \(count) items to \(url.lastPathComponent).", bundle: AppLocale.bundle)
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Step 1 of import: pick the file and read its plaintext header.
    func pickImportFile() -> (url: URL, header: BackupCrypto.Header)? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.fileType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let header = try BackupCrypto.readHeader(try Data(contentsOf: url))
            lastError = nil
            return (url, header)
        } catch {
            lastError = Self.describe(error)
            return nil
        }
    }

    func importFile(_ url: URL, passphrase: String, mode: BackupMode) async {
        do {
            let summary = try await VaultBackup.import(try Data(contentsOf: url), passphrase: passphrase, mode: mode, into: vault)
            lastMessage = String(localized: "Imported \(summary.imported) items, skipped \(summary.skipped) that were newer here.", bundle: AppLocale.bundle)
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    // MARK: Scheduled backups

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Sandbox: the only way to reach this folder again after relaunch.
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try settings.set(Keys.folderBookmark, bookmark.base64EncodedString())
            folderName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setSessionPassphrase(_ passphrase: String) {
        sessionPassphrase = SecretBytes(passphrase)
        hasSessionPassphrase = true
    }

    func clearSessionPassphrase() {
        sessionPassphrase = nil
        hasSessionPassphrase = false
    }

    /// Called after every unlock. Runs when a backup is due and everything
    /// it needs is present; otherwise does nothing quietly.
    func runScheduledBackupIfDue(now: Date = Date()) async {
        guard let interval = schedule.interval, let passphrase = sessionPassphrase,
              let folder = resolveFolder() else { return }
        if let last = lastBackupAt, now.timeIntervalSince(last) < interval { return }
        guard folder.url.startAccessingSecurityScopedResource() else {
            lastError = String(localized: "The backup folder is no longer accessible. Choose it again.", bundle: AppLocale.bundle)
            return
        }
        defer { folder.url.stopAccessingSecurityScopedResource() }
        do {
            let data = try await VaultBackup.export(vault: vault, passphrase: passphrase.string)
            let file = folder.url.appendingPathComponent(Self.fileName(for: now))
            try data.write(to: file, options: .atomic)
            recordBackup(now)
            try prune(in: folder.url)
            lastMessage = String(localized: "Backed up to \(folder.url.lastPathComponent)/\(file.lastPathComponent).", bundle: AppLocale.bundle)
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    // MARK: Helpers

    nonisolated static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return "\(filePrefix)\(formatter.string(from: date)).\(fileExtension)"
    }

    /// Oldest backups beyond `keepCount`, by name — the name carries the
    /// date, so lexical order is chronological.
    nonisolated static func filesToPrune(_ names: [String], keep: Int) -> [String] {
        let ours = names.filter { $0.hasPrefix(filePrefix) && $0.hasSuffix(".\(fileExtension)") }.sorted()
        return ours.count > keep ? Array(ours.prefix(ours.count - keep)) : []
    }

    private func prune(in folder: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        for name in Self.filesToPrune(names, keep: keepCount) {
            try FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private func recordBackup(_ date: Date) {
        lastBackupAt = date
        try? settings.set(Keys.lastAt, String(date.timeIntervalSince1970))
    }

    private func resolveFolder() -> (url: URL, stale: Bool)? {
        guard let raw = try? settings.get(Keys.folderBookmark), let data = Data(base64Encoded: raw) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    static func describe(_ error: any Error) -> String {
        let bundle = AppLocale.bundle
        return switch error {
        case BackupError.wrongPassphraseOrCorrupt: String(localized: "Wrong passphrase, or the file is damaged.", bundle: bundle)
        case BackupError.notABackupFile: String(localized: "That is not a KeyCellar backup file.", bundle: bundle)
        case BackupError.unsupportedVersion(let v): String(localized: "This backup uses format version \(v), which this app can't read.", bundle: bundle)
        case BackupError.passphraseTooShort: String(localized: "The passphrase must be at least \(BackupCrypto.minimumPassphraseLength) characters.", bundle: bundle)
        default: error.localizedDescription
        }
    }
}
