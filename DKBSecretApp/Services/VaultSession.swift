import DKBSecretCore
import Foundation
import Observation

/// Locked / unlocked state of the UI. Locking is cheap and safe to call
/// often: it clears the clipboard if a secret of ours is on it and drops
/// the sealer's cached authentication so the next reveal prompts again.
///
/// Note what locking does *not* need to do: forget any key. Secrets are only
/// ever decrypted on demand through the Secure Enclave; the "unlocked" state
/// gates the UI, the enclave gates the data.
@MainActor
@Observable
final class VaultSession {
    enum State: Equatable {
        case locked
        case unlocked(since: Date)
    }

    private(set) var state: State = .locked
    private(set) var lastUnlockError: String?
    /// For the lock screen's "Locked since"; nil before the first unlock.
    private(set) var lockedAt: Date?

    private let vault: SecretVault
    private let clipboard: ClipboardService
    /// Run after every successful unlock (auto-backup) and on every lock
    /// (drop session-only material like the backup passphrase).
    var onUnlock: [() -> Void] = []
    var onLock: [() -> Void] = []

    init(vault: SecretVault, clipboard: ClipboardService) {
        self.vault = vault
        self.clipboard = clipboard
        #if DEBUG
        // DKB_START_UNLOCKED skips only the lock screen while developing the
        // UI; every reveal still goes through the Secure Enclave. Debug only.
        if ProcessInfo.processInfo.environment["DKB_START_UNLOCKED"] != nil { state = .unlocked(since: Date()) }
        #endif
    }

    var isLocked: Bool { state == .locked }

    /// Touch ID / login password via the sealer. On success the same
    /// authentication serves the first reveals (see `SecretSealing`).
    func unlock() async {
        do {
            try await vault.beginAuthenticationSession()
            state = .unlocked(since: Date())
            lastUnlockError = nil
            onUnlock.forEach { $0() }
        } catch {
            // A dismissed Touch ID sheet is not an error worth a red line.
            lastUnlockError = ItemActions.isUserCancellation(error) ? nil : error.localizedDescription
        }
    }

    func lock() {
        guard !isLocked else { return }
        state = .locked
        lockedAt = Date()
        clipboard.clearIfStillOurs()
        onLock.forEach { $0() }
        Task { await vault.endAuthenticationSession() }
    }
}
