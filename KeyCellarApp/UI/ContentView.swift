import KeyCellarCore
import SwiftUI

/// Sidebar + item list + detail. Settings is a sidebar tab that swaps the
/// list/detail pair for `SettingsView`, as in SignalBar.
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
                AppServices.shared.quickSearch.dismiss()
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
                    // Window toolbar (system treatment, Liquid Glass on
                    // 26+), attached to the detail column so it sits at
                    // the window's trailing edge.
                    .toolbar {
                        // `Spacer` becomes NSToolbar's flexible space, which
                        // is what pushes the button to the right edge.
                        ToolbarItem(placement: .primaryAction) { Spacer() }
                        ToolbarItem(placement: .primaryAction) {
                            if !navigation.sidebarSelection.isTrash { newItemButton }
                        }
                    }
            }
        }
        .onChange(of: navigation.selectedItemId, initial: true) { _, id in detail.show(itemId: id) }
        .sheet(item: $actions.form) { form in
            ItemFormView(model: form) { actions.form = nil }
        }
        .overlay(alignment: .bottom) { CopyToast(clipboard: clipboard) }
        .confirmationDialog(purgeTitle, isPresented: Binding(get: { !actions.pendingPurge.isEmpty }, set: { if !$0 { actions.pendingPurge = [] } })) {
            Button("Delete Permanently", role: .destructive) { actions.confirmPendingPurge() }
        } message: {
            Text("Secrets and history cannot be recovered.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { actions.lastError != nil }, set: { if !$0 { actions.lastError = nil } })) {
            Button("OK") {}
        } message: {
            Text(actions.lastError ?? "")
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first(where: { $0.lastPathComponent.hasPrefix(".env") || $0.pathExtension == "env" }) {
                actions.newEnvSet(fromFile: url)
                return true
            }
            if let url = urls.first(where: { $0.pathExtension.lowercased() == "txt" }) {
                return actions.newRecoveryCodes(fromFile: url)
            }
            return false
        }
    }
}

extension ContentView {
    /// Click adds an item (of the kind the sidebar is showing, if any);
    /// the menu offers every kind and ⌘⇧N's from-clipboard path.
    private var newItemButton: some View {
        Menu {
            ForEach(SecretKind.allCases, id: \.self) { kind in
                Button(kind.singularTitle, systemImage: kind.systemImage) { actions.newItem(kind: kind) }
            }
            Divider()
            Button("New Item from Clipboard…") { actions.newItemFromClipboard() }
        } label: {
            Label("New Item", systemImage: "plus")
        } primaryAction: {
            if case .kind(let kind) = navigation.sidebarSelection {
                actions.newItem(kind: kind)
            } else {
                actions.newItem()
            }
        }
        .help("New Item")
    }

    private var purgeTitle: Text {
        actions.pendingPurge.count == 1
            ? Text("Delete “\(actions.pendingPurge[0].title)” permanently?")
            : Text("Delete \(actions.pendingPurge.count) items permanently?")
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
