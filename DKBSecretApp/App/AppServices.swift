import AppKit
import DKBSecretCore

/// The one place the production object graph is assembled: database at its
/// container path, Secure Enclave master key from the login Keychain,
/// vault, clipboard, session, auto-lock. Views reach it through
/// `AppServices.shared`; tests build the same pieces around
/// `AppDatabase.inMemory()` + `SoftwareSealer` instead.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let database: AppDatabase
    let vault: SecretVault
    let items: ItemRepository
    let projects: ProjectRepository
    let tags: TagRepository
    let settings: SettingsRepository
    let clipboard: ClipboardService
    let session: VaultSession
    let idleMonitor: IdleMonitor
    let actions: ItemActions
    let preferences: AppPreferences
    let backup: BackupManager
    let hotKeys: HotKeyManager
    let quickSearch: QuickSearchPanel
    let expiryNotifier: ExpiryNotifier

    /// Set when the vault could not be brought up. The app shows it and
    /// quits — a vault that silently starts empty would look like data loss.
    let startupFailure: String?

    private init() {
        var failure: String?
        let database: AppDatabase
        let sealer: any SecretSealing
        var enclaveSealer: SecureEnclaveSealer?
        do {
            database = try AppDatabase(path: AppDatabaseLocation.productionPath().path)
        } catch {
            failure = "Can't open the vault database at \(AppDatabaseLocation.productionPath().path): \(error.localizedDescription)"
            database = (try? AppDatabase.inMemory())!
        }
        do {
            #if DEBUG
            let store: any KeychainStoring = DebugKeyBlobStore()
            #else
            let store: any KeychainStoring = KeychainStore()
            #endif
            let blob = try SecureEnclaveSealer.loadOrCreateKeyBlob(keychain: store)
            let enclave = try SecureEnclaveSealer(keyBlob: blob)
            enclaveSealer = enclave
            sealer = enclave
        } catch {
            failure = failure ?? "Can't access the Secure Enclave master key: \(error.localizedDescription)"
            sealer = SoftwareSealer()
        }
        startupFailure = failure

        self.database = database
        vault = SecretVault(database: database, sealer: sealer)
        items = ItemRepository(dbQueue: database.dbQueue)
        projects = ProjectRepository(dbQueue: database.dbQueue)
        tags = TagRepository(dbQueue: database.dbQueue)
        settings = SettingsRepository(dbQueue: database.dbQueue)
        let preferences = AppPreferences(settings: settings)
        self.preferences = preferences
        clipboard = ClipboardService(clearAfterSeconds: { preferences.clipboardSeconds })
        session = VaultSession(vault: vault, clipboard: clipboard)

        let session = self.session
        idleMonitor = IdleMonitor(
            policy: { preferences.autoLock },
            onLock: { session.lock() }
        )
        let actions = ItemActions(vault: vault, items: items, projects: projects, clipboard: clipboard,
                                  navigation: AppNavigationState.shared, expiryPolicy: { preferences.expiry })
        self.actions = actions
        let quickSearchModel = QuickSearchModel(repository: items)
        let quickSearch = QuickSearchPanel(model: quickSearchModel, onCopy: { actions.copyPrimary($0) }, onOpen: { item in
            WindowPresenter.showMainWindow()
            AppNavigationState.shared.sidebarSelection = .section(.all)
            AppNavigationState.shared.show(itemId: item.id)
        })
        self.quickSearch = quickSearch
        hotKeys = HotKeyManager(settings: settings) {
            // Locked: the panel would only show titles, and copying needs the
            // vault open anyway — bring the lock screen up instead.
            session.isLocked ? WindowPresenter.showMainWindow() : quickSearch.toggle()
        }
        expiryNotifier = ExpiryNotifier(items: items, settings: settings) { itemId in
            WindowPresenter.showMainWindow()
            AppNavigationState.shared.sidebarSelection = .section(.expiring)
            AppNavigationState.shared.show(itemId: itemId)
        }
        let backup = BackupManager(vault: vault, settings: settings)
        self.backup = backup
        session.onLock.append { backup.clearSessionPassphrase() }
        session.onUnlock.append { Task { await backup.runScheduledBackupIfDue() } }
        if let enclaveSealer {
            let apply: (Int) -> Void = { seconds in Task { await enclaveSealer.setReuseDuration(TimeInterval(seconds)) } }
            apply(preferences.authReuseSeconds)
            preferences.onAuthReuseChanged = apply
        }
    }
}
