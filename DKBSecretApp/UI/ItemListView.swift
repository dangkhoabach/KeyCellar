import DKBSecretCore
import SwiftUI

struct ItemListView: View {
    @Bindable var navigation: AppNavigationState
    @Bindable var model: ItemListViewModel
    let actions: ItemActions
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                NativeSearchField(text: $model.search, placeholder: String(localized: "Search", bundle: AppLocale.bundle))
                    .focused($searchFocused)
                Menu {
                    Picker("Sort", selection: $model.sort) {
                        Text("Title").tag(ItemQuery.Sort.title)
                        Text("Last Used").tag(ItemQuery.Sort.lastUsed)
                        Text("Created").tag(ItemQuery.Sort.created)
                        Text("Expires").tag(ItemQuery.Sort.expires)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Picker("Environment", selection: $model.environmentFilter) {
                        Text("Any Environment").tag(DeploymentEnvironment?.none)
                        ForEach(DeploymentEnvironment.allCases, id: \.self) { env in
                            Text(env.title).tag(DeploymentEnvironment?.some(env))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Image(systemName: model.environmentFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(10)

            if model.items.isEmpty {
                emptyState
            } else {
                List(model.items, selection: $navigation.selectedItemIds) { item in
                    ItemRowView(item: item)
                        .tag(item.id)
                        .draggable(item.id)
                        .contextMenu { contextMenu(for: item) }
                }
                .onDeleteCommand { actions.trashOrPurgeSelection() }
                .onCopyCommand { actions.copyPrimaryOfSelection(); return [] }
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        .onAppear { model.show(navigation.sidebarSelection) }
        // The selection is cleared by the sidebar itself on a user click, not
        // here: this also fires after `AppNavigationState.show(itemId:)`
        // switched the sidebar, and wiped the item it had just selected.
        .onChange(of: navigation.sidebarSelection) { _, selection in model.show(selection) }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }
    }

    private var emptyState: some View {
        Group {
            if !model.search.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else if navigation.sidebarSelection.isTrash {
                ContentUnavailableView("Trash Is Empty", systemImage: "trash")
            } else {
                ContentUnavailableView {
                    Label("No Items", systemImage: "key")
                } description: {
                    Text("Press ⌘N to add one, ⌘⇧N to create one from the clipboard, or drop a .env file here.")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for item: SecretItem) -> some View {
        if navigation.sidebarSelection.isTrash {
            Button("Restore") { actions.restore(item) }
            Button("Delete Permanently", role: .destructive) { actions.requestPurge(item) }
        } else {
            if item.kind.template.primaryField != nil {
                Button("Copy \(Text(LocalizedStringKey(primaryLabel(item))))") { actions.copyPrimary(item) }
            }
            Button(item.favorite ? "Remove from Favorites" : "Add to Favorites") { actions.toggleFavorite(item) }
            Button("Edit…") { actions.edit(item) }
            Divider()
            Button("Move to Trash", role: .destructive) { actions.trash(item) }
        }
    }

    private func primaryLabel(_ item: SecretItem) -> String {
        item.kind.template.primaryField?.label ?? "Secret"
    }
}

extension Notification.Name {
    /// Posted by the ⌘F command; the list's search field grabs focus.
    static let focusSearch = Notification.Name("DKBSecret.focusSearch")
}
