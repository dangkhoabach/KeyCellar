import AppKit
import KeyCellarCore
import LocalAuthentication
import Observation
import UniformTypeIdentifiers

/// Item operations reachable from more than one place — list context menu,
/// detail buttons, the Item menu and its shortcuts — so each has one
/// implementation. Also owns which form sheet (if any) is showing.
@MainActor
@Observable
final class ItemActions {
    var form: ItemFormModel?
    var lastError: String?
    /// Items waiting for the "delete permanently?" confirmation.
    var pendingPurge: [SecretItem] = []
    /// Which field is being rotated, if the sheet is up.
    var rotating: (item: SecretItem, field: FieldSpec)?

    private let vault: SecretVault
    private let items: ItemRepository
    private let projects: ProjectRepository
    private let clipboard: ClipboardService
    private let navigation: AppNavigationState
    private let expiryPolicy: () -> ExpiryPolicy

    init(vault: SecretVault, items: ItemRepository, projects: ProjectRepository,
         clipboard: ClipboardService, navigation: AppNavigationState, expiryPolicy: @escaping () -> ExpiryPolicy = { ExpiryPolicy() }) {
        self.vault = vault
        self.items = items
        self.projects = projects
        self.clipboard = clipboard
        self.navigation = navigation
        self.expiryPolicy = expiryPolicy
    }

    private func makeForm(_ mode: ItemFormModel.Mode) -> ItemFormModel {
        ItemFormModel(mode: mode, vault: vault, items: items, projects: projects, expiryPolicy: expiryPolicy())
    }

    // MARK: Create / edit

    func newItem() {
        form = makeForm(.create(kind: nil))
    }

    func newItem(kind: SecretKind) {
        form = makeForm(.create(kind: kind))
    }

    /// ⌘⇧N: the clipboard's text becomes the primary secret, with kind and
    /// service guessed from it. Falls back to a plain new-item form.
    func newItemFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let detection = SecretDetector.detect(text)
        let model = makeForm(.create(kind: detection?.kind))
        if let detection {
            model.prefill(from: text, detection: detection)
        }
        form = model
    }

    func newEnvSet(fromFile url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let model = makeForm(.create(kind: .envSet))
        model.title = url.deletingPathExtension().lastPathComponent == "" ? url.lastPathComponent : url.deletingLastPathComponent().lastPathComponent
        model.envText = text
        form = model
    }

    /// A dropped `.txt`: opens the form only when the text reads as a list of
    /// recovery codes, so any other text file is left alone.
    func newRecoveryCodes(fromFile url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8), RecoveryCodes.looksLikeCodeList(text) else { return false }
        let model = makeForm(.create(kind: .recoveryCodes))
        model.title = url.deletingPathExtension().lastPathComponent
        model.loadCodes(text)
        form = model
        return true
    }

    func edit(_ item: SecretItem) {
        let model = makeForm(.edit(item))
        form = model
        Task { await model.loadForEditing() }
    }

    func editSelection() {
        if let item = selectedItem() { edit(item) }
    }

    // MARK: Rotate

    func beginRotate(_ item: SecretItem, field: FieldSpec) {
        rotating = (item, field)
    }

    func rotate(_ item: SecretItem, field: String, newValue: String) {
        let expiry = expiryPolicy().expiryDate(for: item.kind)
        run {
            try await self.vault.rotate(itemId: item.id, field: field, newValue: SecretBytes(newValue))
            try await self.vault.setExpiry(itemId: item.id, to: expiry)
        }
    }

    /// The key was rotated at the provider and the new value entered by
    /// hand elsewhere: only the expiry moves.
    func markRotated(_ item: SecretItem) {
        let expiry = expiryPolicy().expiryDate(for: item.kind)
        run { try await self.vault.setExpiry(itemId: item.id, to: expiry) }
    }

    // MARK: Copy

    func copyPrimary(_ item: SecretItem) {
        if item.kind == .recoveryCodes {
            copyRecoveryCode(item)
            return
        }
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

    // MARK: Recovery codes

    /// Copies one code — `index` (1-based), or the first unused one — and
    /// marks it used: a code pasted into a sign-in form is spent.
    /// The whole set is never copied. Reads the item fresh so a stale row
    /// from the list or quick search can't hand out a code already used.
    func copyRecoveryCode(_ item: SecretItem, index: Int? = nil) {
        guard let current = try? items.fetch(id: item.id), current.deletedAt == nil else { return }
        var used = current.usedRecoveryCodes
        guard let target = index ?? (1...max(current.recoveryCodeCount, 1)).first(where: { used[$0] == nil }),
              target <= current.recoveryCodeCount else {
            lastError = String(localized: "No unused codes left.", bundle: AppLocale.bundle)
            return
        }
        Task {
            do {
                let codes = try await vault.reveal(itemId: item.id, field: "codes").string.split(separator: "\n")
                guard codes.indices.contains(target - 1) else { return }
                clipboard.copy(SecretBytes(String(codes[target - 1])))
                used[target] = used[target] ?? Date()
                try items.setUsedRecoveryCodes(used, itemId: item.id)
            } catch {
                report(error)
            }
        }
    }

    func setRecoveryCode(_ item: SecretItem, index: Int, used isUsed: Bool) {
        guard let current = try? items.fetch(id: item.id) else { return }
        var used = current.usedRecoveryCodes
        used[index] = isUsed ? (used[index] ?? Date()) : nil
        do { try items.setUsedRecoveryCodes(used, itemId: item.id) } catch { report(error) }
    }

    /// The provider issued a new set: the edit sheet with an empty editor.
    func replaceCodes(_ item: SecretItem) {
        let model = makeForm(.edit(item))
        model.replacingCodes = true
        form = model
    }

    /// Writes the set as `RecoveryCodes.serialize` does (used codes marked
    /// `[x] `, so importing the file keeps them), mode 0600. The caller has
    /// already shown the "this is plaintext" confirmation.
    func exportRecoveryCodes(_ item: SecretItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(item.title).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let codes = try await vault.reveal(itemId: item.id, field: "codes").string.split(separator: "\n")
                let used = (try items.fetch(id: item.id) ?? item).usedRecoveryCodes
                let text = RecoveryCodes.serialize(codes.enumerated().map { .init(String($1), used: used[$0 + 1] != nil) })
                try (text + "\n").write(to: url, atomically: true, encoding: .utf8)
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

    /// Every permanent delete — button, context menu, ⌫ in the Trash, ⌘⇧⌫ —
    /// goes through the confirmation in `ContentView` first.
    func requestPurge(_ items: [SecretItem]) {
        if !items.isEmpty { pendingPurge = items }
    }

    func requestPurge(_ item: SecretItem) {
        requestPurge([item])
    }

    func confirmPendingPurge() {
        for item in pendingPurge {
            run { try await self.vault.purge(itemId: item.id) }
            navigation.selectedItemIds.remove(item.id)
        }
        pendingPurge = []
    }

    /// ⌫ on the list: Trash normally, permanent delete when viewing the Trash.
    func trashOrPurgeSelection() {
        if navigation.sidebarSelection.isTrash {
            purgeSelection()
            return
        }
        for id in navigation.selectedItemIds {
            if let item = try? items.fetch(id: id) { trash(item) }
        }
    }

    func purgeSelection() {
        requestPurge(navigation.selectedItemIds.compactMap { try? items.fetch(id: $0) })
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
