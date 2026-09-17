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

    private let vault: SecretVault
    private let clipboard: ClipboardService

    init(vault: SecretVault, clipboard: ClipboardService) {
        self.vault = vault
        self.clipboard = clipboard
    }

    var isLocked: Bool { state == .locked }

    /// Touch ID / login password via the sealer. On success the same
    /// authentication serves the first reveals (see `SecretSealing`).
    func unlock() async {
        do {
            try await vault.beginAuthenticationSession()
            state = .unlocked(since: Date())
            lastUnlockError = nil
        } catch {
            lastUnlockError = error.localizedDescription
        }
    }

    func lock() {
        guard !isLocked else { return }
        state = .locked
        clipboard.clearIfStillOurs()
        Task { await vault.endAuthenticationSession() }
    }
}
