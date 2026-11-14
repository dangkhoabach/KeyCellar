import KeyCellarCore
import SwiftUI

/// The menu bar panel, laid out as in the author's other menu bar apps: a
/// header, the quick search when the vault is unlocked (or the way to unlock
/// it), and a footer with the app-level actions.
struct MenuBarPanelView: View {
    static let width: CGFloat = 360

    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue
    /// Counts the openings: the content is made again for each, so it
    /// unlocks or focuses the search as it appears.
    @State private var opening = 0

    var body: some View {
        // The panel is not part of a SwiftUI scene, so the in-app language is
        // applied here rather than inherited.
        MenuBarPanelContent()
            .id(opening)
            .environment(\.locale, (AppLocale(rawValue: languageRaw) ?? .systemDefault).locale)
            .frame(width: Self.width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                StatusBarController.shared.fitPanel(height: height)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .onReceive(NotificationCenter.default.publisher(for: .menuBarPanelOpened)) { _ in opening += 1 }
    }
}

private struct MenuBarPanelContent: View {
    private let services = AppServices.shared
    @State private var model = QuickSearchModel(repository: AppServices.shared.items, limit: 5)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "KeyCellar").font(.headline)
                Spacer()
                Label(services.session.isLocked ? "Locked" : "Unlocked",
                      systemImage: services.session.isLocked ? "lock.fill" : "lock.open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
            Divider()
            if services.session.isLocked {
                // Opening the panel while locked asks for Touch ID right
                // away, so a search is one click from the menu bar; the
                // button is the retry.
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text("Vault is locked")
                    Spacer()
                    Button("Unlock…") { unlock() }
                        .disabled(services.session.isUnlocking)
                }
                .padding(14)
                .onAppear { unlock() }
            } else {
                QuickSearchView(model: model,
                                onCopy: { item in
                                    services.actions.copyPrimary(item)
                                    StatusBarController.shared.closePanel()
                                },
                                onOpen: { open($0) },
                                onDismiss: { StatusBarController.shared.closePanel() })
                    .onAppear { model.search() }
            }
            Divider()
            footer
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("Show KeyCellar", systemImage: "macwindow") { WindowPresenter.showMainWindow() }
            if !services.session.isLocked {
                footerButton("Lock Now", systemImage: "lock") { services.session.lock() }
            }
            footerButton("Settings…", systemImage: "gearshape") { WindowPresenter.showSettings() }
            Spacer()
            footerButton("Quit KeyCellar", systemImage: "power") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func footerButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }

    private func unlock() {
        Task {
            await services.session.unlock()
            StatusBarController.shared.regainFocus()
        }
    }

    private func open(_ item: SecretItem) {
        StatusBarController.shared.closePanel()
        WindowPresenter.showMainWindow()
        AppNavigationState.shared.sidebarSelection = .section(.all)
        AppNavigationState.shared.show(itemId: item.id)
    }
}
