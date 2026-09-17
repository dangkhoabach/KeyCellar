import DKBSecretCore
import Foundation
import Observation

/// Every user-tunable security setting, persisted in the `settings` table
/// the moment it changes. Services read from here (through closures, so
/// they stay testable without an `AppPreferences`), rather than keeping
/// copies that could drift.
@MainActor
@Observable
final class AppPreferences {
    static let clipboardChoices = [15, 30, 45, 60, 120]
    static let revealChoices = [15, 30, 60]
    /// 0 = every reveal prompts. 300 is macOS's own ceiling for reuse.
    static let authReuseChoices = [0, 10, 30, 60, 300]

    var autoLock: AutoLockPolicy { didSet { try? autoLock.save(to: settings) } }
    var clipboardSeconds: Int { didSet { try? settings.set(Keys.clipboard, String(clipboardSeconds)) } }
    var revealSeconds: Int { didSet { try? settings.set(Keys.reveal, String(revealSeconds)) } }
    var authReuseSeconds: Int {
        didSet {
            try? settings.set(Keys.authReuse, String(authReuseSeconds))
            onAuthReuseChanged?(authReuseSeconds)
        }
    }

    /// Set by `AppServices` to push the value into the Secure Enclave sealer.
    var onAuthReuseChanged: ((Int) -> Void)?

    private let settings: SettingsRepository

    enum Keys {
        static let clipboard = "clipboard.clearSeconds"
        static let reveal = "reveal.hideSeconds"
        static let authReuse = "auth.reuseSeconds"
    }

    init(settings: SettingsRepository) {
        self.settings = settings
        autoLock = (try? AutoLockPolicy.load(from: settings)) ?? AutoLockPolicy()
        clipboardSeconds = Self.read(Keys.clipboard, from: settings, in: Self.clipboardChoices) ?? 45
        revealSeconds = Self.read(Keys.reveal, from: settings, in: Self.revealChoices) ?? 30
        authReuseSeconds = Self.read(Keys.authReuse, from: settings, in: Self.authReuseChoices) ?? 30
    }

    /// Unknown or tampered values fall back to the default rather than, say,
    /// a 0-second clipboard timeout becoming "never clear".
    private static func read(_ key: String, from settings: SettingsRepository, in choices: [Int]) -> Int? {
        guard let raw = try? settings.get(key), let value = Int(raw), choices.contains(value) else { return nil }
        return value
    }
}
