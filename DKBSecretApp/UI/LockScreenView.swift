import AppKit
import SwiftUI

/// Replaces the whole window content while the vault is locked (plan §7.3).
/// Touch ID is prompted automatically whenever the user comes to the app and
/// finds it locked (launch, switching back from another app, unlocking the
/// Mac) — the way Apple's Passwords app behaves. It is never prompted behind
/// the user's back: a login item starts in the background and waits for the
/// first click, and a lock taken while the app is frontmost (⌘L, idle) just
/// shows the button.
struct LockScreenView: View {
    let session: VaultSession
    /// Armed while the app is in the background so the next activation
    /// prompts exactly once. Not armed by the Touch ID sheet itself taking
    /// focus, or a cancelled sheet would re-prompt forever.
    @State private var promptOnActivate = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("DKB Secret")
                .font(.title.bold())
            if let since = session.lockedAt {
                Text("Locked since \(since, format: .dateTime.hour().minute())")
                    .foregroundStyle(.secondary)
            }
            Button {
                unlock()
            } label: {
                Label("Unlock with Touch ID", systemImage: "touchid")
                    .frame(minWidth: 200)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(session.isUnlocking)
            if let error = session.lastUnlockError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            // Fresh launch (never unlocked yet): prompt now if we are
            // frontmost, otherwise on the first activation.
            if session.lockedAt == nil {
                promptOnActivate = true
                promptIfActive()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if !session.isUnlocking { promptOnActivate = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if promptOnActivate { promptIfActive() }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsUnlocked"))) { _ in
            // Auto-lock on screen lock / sleep leaves us frontmost with no
            // activation change, so this is the "came back to the Mac" cue.
            promptIfActive()
        }
    }

    private func promptIfActive() {
        guard NSApp.isActive, !session.isUnlocking else { return }
        promptOnActivate = false
        unlock()
    }

    private func unlock() {
        Task { await session.unlock() }
    }
}
