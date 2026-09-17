import Foundation

/// `~/Library/Containers/com.dangkhoabach.dkb-secret/Data/Library/Application Support/dkb-secret.db`
/// — the sandbox container's Application Support directory (plan D14). The
/// file holds metadata and ciphertext only.
enum AppDatabaseLocation {
    static func productionPath() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dkb-secret.db")
    }
}
