import AppKit
import DKBSecretCore
import Observation

/// Copies a secret the way a password manager should (plan §2 T5): marked
/// with `org.nspasteboard.ConcealedType` so clipboard managers skip it, and
/// cleared again after `clearAfterSeconds` — unless the user has copied
/// something else since, which is theirs to keep.
@MainActor
@Observable
final class ClipboardService {
    /// The de-facto standard clipboard managers honour (Raycast, Paste,
    /// Alfred, 1Password all write or respect it).
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    var clearAfterSeconds = 45
    /// Countdown for the UI; `nil` when nothing of ours is on the pasteboard.
    private(set) var remainingSeconds: Int?

    private let pasteboard: NSPasteboard
    private var ownedChangeCount: Int?
    private var countdown: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ secret: SecretBytes) {
        countdown?.cancel()
        pasteboard.clearContents()
        pasteboard.setString(secret.string, forType: .string)
        pasteboard.setString("", forType: Self.concealedType)
        ownedChangeCount = pasteboard.changeCount
        remainingSeconds = clearAfterSeconds

        countdown = Task { [weak self] in
            while let self, let remaining = remainingSeconds, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                // Someone else took the pasteboard: stop counting, leave it alone.
                guard pasteboard.changeCount == ownedChangeCount else {
                    forget()
                    return
                }
                remainingSeconds = remaining - 1
            }
            self?.clearIfStillOurs()
        }
    }

    /// Wipes the pasteboard only if it still holds what we put there —
    /// called by the countdown, and immediately when the vault locks.
    func clearIfStillOurs() {
        countdown?.cancel()
        if let owned = ownedChangeCount, pasteboard.changeCount == owned {
            pasteboard.clearContents()
        }
        forget()
    }

    private func forget() {
        ownedChangeCount = nil
        remainingSeconds = nil
    }
}
