import SwiftUI

/// Placeholder menu bar dropdown. Phase 7 replaces the body with quick search
/// and "Lock now"; the Open/Quit items stay.
struct MenuBarContentView: View {
    private let session = AppServices.shared.session

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DKB Secret")
                .font(.headline)
            Divider()
            if session.isLocked {
                Button("Unlock…") { WindowPresenter.showMainWindow() }
            } else {
                Button("Lock Now") { session.lock() }
            }
            Button("Open DKB Secret") { WindowPresenter.showMainWindow() }
            Button("Settings…") { WindowPresenter.showSettings() }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: 220)
    }
}
