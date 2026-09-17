#if DEBUG
import DKBSecretCore
import Foundation

/// Debug builds only. The login Keychain pins an item to the cdhash of the
/// app that created it (`partition_id`), and every Debug build has a new
/// cdhash — so each rebuild would stop on a "wants to access key… enter the
/// login keychain password" dialog. Debug builds keep the enclave key blob
/// in their sandbox container instead. The blob is still useless without
/// this Mac's Secure Enclave and a Touch ID; what is lost is only the
/// login-password gate, and only for Debug. Release uses `KeychainStore`.
struct DebugKeyBlobStore: KeychainStoring {
    private var url: URL {
        AppDatabaseLocation.productionPath().deletingLastPathComponent().appendingPathComponent("master-key-debug.blob")
    }

    func readMasterKeyBlob() throws -> Data? {
        FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    func writeMasterKeyBlob(_ blob: Data) throws {
        try blob.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func deleteMasterKeyBlob() throws {
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
