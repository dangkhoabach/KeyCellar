import Foundation
import Security

public enum KeychainStoreError: Error, Equatable {
    case unhandledStatus(OSStatus)
}

/// Exactly one item ever goes into the Keychain: the Secure Enclave key
/// blob. The protocol exists so `SecretVault` and the app's bootstrap can be
/// tested against `InMemoryKeychainStore` — the real Keychain isn't reachable
/// from `swift test`.
public protocol KeychainStoring: Sendable {
    func readMasterKeyBlob() throws -> Data?
    func writeMasterKeyBlob(_ blob: Data) throws
    func deleteMasterKeyBlob() throws
}

/// Login-Keychain (file-based) item, deliberately not the data-protection
/// keychain: that one needs a Team-ID entitlement this unsigned-by-Apple app
/// can't have (`errSecMissingEntitlement`, confirmed by testing). The login
/// Keychain still gives the blob an ACL bound to this app's code identity
/// and encryption under the login password. The blob itself is useless
/// without this Mac's Secure Enclave and a Touch ID, so this is the second
/// layer, not the only one (threat model T2).
public struct KeychainStore: KeychainStoring {
    private static let service = "com.dangkhoabach.dkb-secret"
    private static let account = "vault-master-key"

    public init() {}

    public func readMasterKeyBlob() throws -> Data? {
        try Self.onMainThread {
            var query = Self.baseQuery
            query[kSecReturnData as String] = true
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess: return result as? Data
            case errSecItemNotFound: return nil
            default: throw KeychainStoreError.unhandledStatus(status)
            }
        }
    }

    public func writeMasterKeyBlob(_ blob: Data) throws {
        try Self.onMainThread {
            // Delete-then-add rather than SecItemUpdate: the simplest way to
            // guarantee a stale item with different attributes never lingers.
            SecItemDelete(Self.baseQuery as CFDictionary)
            var query = Self.baseQuery
            query[kSecValueData as String] = blob
            // What Keychain Access shows instead of the raw service name.
            query[kSecAttrLabel as String] = "DKB Secret – vault master key"
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainStoreError.unhandledStatus(status) }
        }
    }

    public func deleteMasterKeyBlob() throws {
        try Self.onMainThread {
            let status = SecItemDelete(Self.baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainStoreError.unhandledStatus(status)
            }
        }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false,
        ]
    }

    /// Keychain access can put up system UI (an ACL confirmation); Apple's
    /// guidance is to make such calls from the main thread. Same routing as
    /// DKB Monitor's `KeychainStore`.
    private static func onMainThread<T: Sendable>(_ body: @Sendable () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try body()
        }
        var result: Result<T, Error>!
        DispatchQueue.main.sync {
            result = Result { try body() }
        }
        return try result.get()
    }
}
