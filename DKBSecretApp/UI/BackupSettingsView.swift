import DKBSecretCore
import SwiftUI

/// Settings › Backup: manual export/import and the scheduled backups.
struct BackupSettingsView: View {
    @Bindable var backup: BackupManager

    private enum Sheet: Identifiable {
        case exportPassphrase
        case sessionPassphrase
        case importFile(URL, BackupCrypto.Header)

        var id: String {
            switch self {
            case .exportPassphrase: "export"
            case .sessionPassphrase: "session"
            case .importFile(let url, _): "import-\(url.path)"
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var busy = false

    var body: some View {
        Form {
            sections
        }
        .formStyle(.grouped)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .exportPassphrase:
                PassphraseSheet(purpose: .create(title: "Choose a passphrase for this backup")) { passphrase in
                    self.sheet = nil
                    run { await backup.exportNow(passphrase: passphrase) }
                } onCancel: { self.sheet = nil }
            case .sessionPassphrase:
                PassphraseSheet(purpose: .create(title: "Passphrase for scheduled backups")) { passphrase in
                    backup.setSessionPassphrase(passphrase)
                    self.sheet = nil
                    run { await backup.runScheduledBackupIfDue() }
                } onCancel: { self.sheet = nil }
            case .importFile(let url, let header):
                ImportSheet(header: header) { passphrase, mode in
                    self.sheet = nil
                    run { await backup.importFile(url, passphrase: passphrase, mode: mode) }
                } onCancel: { self.sheet = nil }
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        Section("Backup File") {
            LabeledContent("Last backup") {
                if let date = backup.lastBackupAt {
                    Text(date, format: .relative(presentation: .named))
                        .foregroundStyle(backup.isStale ? Color.orange : Color.secondary)
                } else {
                    Text("Never").foregroundStyle(.orange)
                }
            }
            HStack {
                Button("Export Now…") { sheet = .exportPassphrase }
                Button("Import…") {
                    if let picked = backup.pickImportFile() { sheet = .importFile(picked.url, picked.header) }
                }
            }
            .disabled(busy)
            Text("A backup holds every item, its history and the Trash, encrypted with a passphrase of your choosing. Because the vault is bound to this Mac's Secure Enclave, a backup is the only way to move or recover it.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Scheduled Backups") {
            Picker("Schedule", selection: $backup.schedule) {
                Text("Off").tag(BackupManager.Schedule.off)
                Text("Daily").tag(BackupManager.Schedule.daily)
                Text("Weekly").tag(BackupManager.Schedule.weekly)
            }
            LabeledContent("Folder") {
                HStack {
                    Text(backup.folderName ?? "Not chosen").foregroundStyle(.secondary)
                    Button("Choose…") { backup.chooseFolder() }
                }
            }
            Picker("Keep the latest", selection: $backup.keepCount) {
                ForEach(BackupManager.keepChoices, id: \.self) { Text("\($0) backups").tag($0) }
            }
            LabeledContent("Passphrase for this session") {
                HStack {
                    Text(backup.hasSessionPassphrase ? "Set" : "Not set").foregroundStyle(.secondary)
                    Button(backup.hasSessionPassphrase ? "Change…" : "Set…") { sheet = .sessionPassphrase }
                }
            }
            Text("Scheduled backups run right after you unlock the vault, when a backup is due. The passphrase is kept only until the vault locks, so it has to be entered again each session.")
                .font(.callout).foregroundStyle(.secondary)
        }
        if backup.lastMessage != nil || backup.lastError != nil {
            Section {
                if let message = backup.lastMessage { Label(message, systemImage: "checkmark.circle") }
                if let error = backup.lastError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
        }
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        busy = true
        Task {
            await body()
            busy = false
        }
    }
}

/// Import: shows what the file claims to contain, asks how to apply it and
/// for its passphrase.
struct ImportSheet: View {
    let header: BackupCrypto.Header
    let onConfirm: (String, BackupMode) -> Void
    let onCancel: () -> Void
    @State private var passphrase = ""
    @State private var replace = false
    @State private var confirmReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Backup").font(.title3.bold())
            Text("\(header.itemCount) items, created \(header.createdAt, format: .dateTime.day().month().year().hour().minute()).")
                .foregroundStyle(.secondary)
            Picker("Mode", selection: $replace) {
                Text("Merge — keep the newer copy of each item").tag(false)
                Text("Replace — erase this vault first").tag(true)
            }
            .pickerStyle(.radioGroup)
            if replace {
                Text("Everything currently in this vault, including the Trash, is deleted before the backup is loaded.")
                    .font(.callout).foregroundStyle(.red)
            }
            SecureField("Passphrase", text: $passphrase)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(replace ? "Replace Vault" : "Import") {
                    replace ? confirmReplace = true : onConfirm(passphrase, .merge)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(passphrase.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .confirmationDialog("Erase this vault and load the backup?", isPresented: $confirmReplace) {
            Button("Replace Vault", role: .destructive) { onConfirm(passphrase, .replace) }
        } message: {
            Text("Every current item, its history and the Trash will be gone. The import is applied only if the whole file decrypts and loads.")
        }
    }
}
