import Foundation

/// `~/Library/Containers/com.dangkhoabach.dkb-secret/Data/Library/Application Support/dkb-secret.db`
/// — the sandbox container's Application Support directory. The
/// file holds metadata and ciphertext only.
enum AppDatabaseLocation {
    static func productionPath() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // Debug builds keep their own file so seeding sample data or testing
        // a migration never touches the vault the Release build in
        // /Applications is using. Debug also has its own enclave key blob
        // (`DebugKeyBlobStore`), so the two vaults share nothing.
        #if DEBUG
        return base.appendingPathComponent("dkb-secret-debug.db")
        #else
        return base.appendingPathComponent("dkb-secret.db")
        #endif
    }

    #if DEBUG
    /// `--reset-debug-vault`: wipes the Debug database and its enclave key
    /// blob so a run starts empty (the shell can't reach inside the sandbox
    /// container to do it). Debug builds only.
    static func resetDebugVault() {
        let dir = productionPath().deletingLastPathComponent()
        for name in ["dkb-secret-debug.db", "dkb-secret-debug.db-wal", "dkb-secret-debug.db-shm", "master-key-debug.blob"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
    #endif
}
