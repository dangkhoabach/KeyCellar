import AppKit
import DKBSecretCore
import LocalAuthentication
import Observation

/// Item operations reachable from more than one place — list context menu,
/// detail buttons, the Item menu and its shortcuts — so each has one
/// implementation. Also owns which form sheet (if any) is showing.
@MainActor
@Observable
final class ItemActions {
    var form: ItemFormModel?
    var lastError: String?

    private let vault: SecretVault
    private let items: ItemRepository
    private let projects: ProjectRepository
    private let clipboard: ClipboardService
    private let navigation: AppNavigationState

    init(vault: SecretVault, items: ItemRepository, projects: ProjectRepository,
         clipboard: ClipboardService, navigation: AppNavigationState) {
        self.vault = vault
        self.items = items
        self.projects = projects
        self.clipboard = clipboard
        self.navigation = navigation
    }

    // MARK: Create / edit

    func newItem() {
        form = ItemFormModel(mode: .create(kind: nil), vault: vault, items: items, projects: projects)
    }

    func newItem(kind: SecretKind) {
        form = ItemFormModel(mode: .create(kind: kind), vault: vault, items: items, projects: projects)
    }

    /// ⌘⇧N: the clipboard's text becomes the primary secret, with kind and
    /// service guessed from it. Falls back to a plain new-item form.
    func newItemFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let detection = SecretDetector.detect(text)
        let model = ItemFormModel(mode: .create(kind: detection?.kind), vault: vault, items: items, projects: projects)
        if let detection {
            model.prefill(from: text, detection: detection)
        }
        form = model
    }

    func newEnvSet(fromFile url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let model = ItemFormModel(mode: .create(kind: .envSet), vault: vault, items: items, projects: projects)
        model.title = url.deletingPathExtension().lastPathComponent == "" ? url.lastPathComponent : url.deletingLastPathComponent().lastPathComponent
        model.envText = text
        form = model
    }

    func edit(_ item: SecretItem) {
        let model = ItemFormModel(mode: .edit(item), vault: vault, items: items, projects: projects)
        form = model
        Task { await model.loadForEditing() }
    }

    func editSelection() {
        if let item = selectedItem() { edit(item) }
    }

    // MARK: Copy

    func copyPrimary(_ item: SecretItem) {
        guard let field = item.kind.template.primaryField else { return }
        copy(item, field: field.key)
    }

    func copyPrimaryOfSelection() {
        if let item = selectedItem() { copyPrimary(item) }
    }

    func copy(_ item: SecretItem, field: String, slot: Int = 0) {
        Task {
            do {
                let secret = try await vault.reveal(itemId: item.id, field: field, slot: slot)
                clipboard.copy(secret)
            } catch {
                report(error)
            }
        }
    }

    func copyMetadata(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyUsernameOfSelection() { copyMetadata(selectedItem()?.username) }
    func copyURLOfSelection() { copyMetadata(selectedItem()?.url) }

    /// Writes the set's KEY=VALUE pairs to a file the user picks, mode 0600.
    /// The caller has already shown the "this is plaintext" confirmation.
    func exportEnvFile(_ item: SecretItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ".env"
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                var pairs: [DotEnvFile.Pair] = []
                for blob in try items.blobs(for: item.id) where blob.slot == 0 && blob.field.hasPrefix(SecretItem.envFieldPrefix) {
                    let value = try await vault.reveal(itemId: item.id, field: blob.field)
                    pairs.append((String(blob.field.dropFirst(SecretItem.envFieldPrefix.count)), value.string))
                }
                try DotEnvFile.serialize(pairs).write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                report(error)
            }
        }
    }

    // MARK: Favorite / trash

    func toggleFavorite(_ item: SecretItem) {
        try? items.setFavorite(!item.favorite, itemId: item.id)
    }

    func trash(_ item: SecretItem) {
        run { try await self.vault.moveToTrash(itemId: item.id) }
        navigation.selectedItemIds.remove(item.id)
    }

    func restore(_ item: SecretItem) {
        run { try await self.vault.restore(itemId: item.id) }
    }

    func purge(_ item: SecretItem) {
        run { try await self.vault.purge(itemId: item.id) }
        navigation.selectedItemIds.remove(item.id)
    }

    /// ⌫ on the list: Trash normally, permanent delete when viewing the Trash.
    func trashOrPurgeSelection() {
        for id in navigation.selectedItemIds {
            guard let item = try? items.fetch(id: id) else { continue }
            navigation.sidebarSelection.isTrash ? purge(item) : trash(item)
        }
    }

    func purgeSelection() {
        for id in navigation.selectedItemIds {
            if let item = try? items.fetch(id: id) { purge(item) }
        }
    }

    // MARK: Helpers

    private func selectedItem() -> SecretItem? {
        navigation.selectedItemId.flatMap { try? items.fetch(id: $0) }
    }

    private func run(_ body: @escaping @Sendable () async throws -> Void) {
        Task {
            do { try await body() } catch { report(error) }
        }
    }

    /// Cancelled Touch ID is silent; anything else becomes the alert in `ContentView`.
    func report(_ error: any Error) {
        if Self.isUserCancellation(error) { return }
        lastError = error.localizedDescription
    }

    /// The enclave wraps a dismissed Touch ID sheet in a CryptoTokenKit
    /// error whose underlying error is `LAError.userCancel`; walk the chain.
    nonisolated static func isUserCancellation(_ error: any Error) -> Bool {
        var current: NSError? = error as NSError
        while let e = current {
            if e.domain == LAError.errorDomain,
               [LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue].contains(e.code) {
                return true
            }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
