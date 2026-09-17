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

    /// Set when the vault could not be brought up. The app shows it and
    /// quits — a vault that silently starts empty would look like data loss.
    let startupFailure: String?

    private init() {
        var failure: String?
        let database: AppDatabase
        let sealer: any SecretSealing
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
            sealer = try SecureEnclaveSealer(keyBlob: blob)
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
        clipboard = ClipboardService()
        session = VaultSession(vault: vault, clipboard: clipboard)

        let settings = self.settings
        let session = self.session
        idleMonitor = IdleMonitor(
            policy: { (try? AutoLockPolicy.load(from: settings)) ?? AutoLockPolicy() },
            onLock: { session.lock() }
        )
        actions = ItemActions(vault: vault, items: items, projects: projects, clipboard: clipboard, navigation: AppNavigationState.shared)
    }
}
