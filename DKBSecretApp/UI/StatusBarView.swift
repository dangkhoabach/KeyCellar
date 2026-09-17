import SwiftUI

/// The strip under the split view: when the vault will auto-lock, and how
/// long a copied secret stays on the clipboard (plan §7.3). Redraws once a
/// second only while it has something to count down.
struct StatusBarView: View {
    let preferences: AppPreferences
    let clipboard: ClipboardService
    let backup: BackupManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 16) {
                if preferences.autoLock.idleTimeout != .never {
                    let remaining = max(0, Double(preferences.autoLock.idleTimeout.rawValue) - IdleMonitor.secondsSinceLastInput())
                    Label("Auto-lock in \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))", systemImage: "lock")
                }
                if let seconds = clipboard.remainingSeconds {
                    Label("Clipboard clears in \(seconds)s", systemImage: "doc.on.clipboard")
                }
                Spacer()
                if backup.isStale {
                    Label(backup.lastBackupAt == nil ? "No backup yet" : "Last backup \(backup.daysSinceLastBackup ?? 0) days ago", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                let _ = context.date
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
    }
}
