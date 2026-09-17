import SwiftUI

/// Replaces the whole window content while the vault is locked (plan §7.3).
/// Deliberately no automatic Touch ID prompt on appear: with Launch at Login
/// on, that would raise a Touch ID sheet at every login before the user has
/// asked for anything.
struct LockScreenView: View {
    let session: VaultSession
    @State private var unlocking = false

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
                unlocking = true
                Task {
                    await session.unlock()
                    unlocking = false
                }
            } label: {
                Label("Unlock with Touch ID", systemImage: "touchid")
                    .frame(minWidth: 200)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(unlocking)
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
    }
}
