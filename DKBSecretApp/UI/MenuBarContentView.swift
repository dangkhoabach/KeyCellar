import DKBSecretCore
import SwiftUI

/// The menu bar dropdown: quick search on top when unlocked, then Lock /
/// Open / Settings / Quit.
struct MenuBarContentView: View {
    private let services = AppServices.shared
    @State private var model = QuickSearchModel(repository: AppServices.shared.items, limit: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if services.session.isLocked {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text("Vault is locked")
                    Spacer()
                    Button("Unlock…") { WindowPresenter.showMainWindow() }
                }
                .padding(12)
            } else {
                QuickSearchView(model: model, onCopy: { services.actions.copyPrimary($0) },
                                onOpen: { open($0) }, onDismiss: {})
                    .onAppear { model.search() }
            }
            Divider()
            HStack(spacing: 12) {
                if !services.session.isLocked {
                    Button("Lock Now") { services.session.lock() }
                }
                Button("Open") { WindowPresenter.showMainWindow() }
                Button("Settings…") { WindowPresenter.showSettings() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(10)
        }
        .frame(width: 360)
    }

    private func open(_ item: SecretItem) {
        WindowPresenter.showMainWindow()
        AppNavigationState.shared.sidebarSelection = .section(.all)
        AppNavigationState.shared.show(itemId: item.id)
    }
}
