import DKBSecretCore
import SwiftUI

/// Sidebar + item list + detail. Settings is a sidebar tab that swaps the
/// list/detail pair for `SettingsView` (Phase 5), as in DKB Monitor.
struct ContentView: View {
    @Bindable private var navigation = AppNavigationState.shared
    @State private var sidebar: SidebarViewModel
    @State private var list: ItemListViewModel
    @State private var detail: ItemDetailViewModel
    @Bindable private var actions: ItemActions
    private let clipboard: ClipboardService
    private let session: VaultSession
    private let preferences: AppPreferences
    private let backup: BackupManager
    @State private var settingsSection: SettingsSection = .general

    init(services: AppServices = .shared) {
        _sidebar = State(initialValue: SidebarViewModel(database: services.database, projects: services.projects, tags: services.tags))
        _list = State(initialValue: ItemListViewModel(repository: services.items, dbQueue: services.database.dbQueue))
        let preferences = services.preferences
        _detail = State(initialValue: ItemDetailViewModel(vault: services.vault, dbQueue: services.database.dbQueue, revealSeconds: { preferences.revealSeconds }))
        actions = services.actions
        clipboard = services.clipboard
        session = services.session
        self.preferences = preferences
        backup = services.backup
    }

    var body: some View {
        Group {
            if session.isLocked {
                // Replaced, not overlaid: nothing of the vault is in the view
                // hierarchy while locked.
                LockScreenView(session: session)
            } else {
                splitView
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        StatusBarView(preferences: preferences, clipboard: clipboard, backup: backup)
                    }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .onChange(of: session.isLocked) { _, locked in
            if locked {
                detail.hideAll()
                actions.form = nil
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(navigation: navigation, model: sidebar)
        } content: {
            if navigation.sidebarSelection.isSettings {
                SettingsSectionList(selection: $settingsSection)
            } else {
                ItemListView(navigation: navigation, model: list, actions: actions)
            }
        } detail: {
            if navigation.sidebarSelection.isSettings {
                SettingsView(section: settingsSection, preferences: preferences, backup: backup)
            } else {
                ItemDetailView(model: detail, actions: actions, inTrash: navigation.sidebarSelection.isTrash)
            }
        }
        .onChange(of: navigation.selectedItemId, initial: true) { _, id in detail.show(itemId: id) }
        .sheet(item: $actions.form) { form in
            ItemFormView(model: form) { actions.form = nil }
        }
        .overlay(alignment: .bottom) { CopyToast(clipboard: clipboard) }
        .alert("Something went wrong", isPresented: Binding(get: { actions.lastError != nil }, set: { if !$0 { actions.lastError = nil } })) {
            Button("OK") {}
        } message: {
            Text(actions.lastError ?? "")
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.lastPathComponent.hasPrefix(".env") || $0.pathExtension == "env" }) else { return false }
            actions.newEnvSet(fromFile: url)
            return true
        }
    }
}

/// "Copied — clears in 45s", driven by the clipboard's own countdown.
struct CopyToast: View {
    let clipboard: ClipboardService

    var body: some View {
        if let remaining = clipboard.remainingSeconds {
            Label("Copied — clears in \(remaining)s", systemImage: "doc.on.clipboard")
                .font(.callout)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.default, value: remaining)
        }
    }
}
