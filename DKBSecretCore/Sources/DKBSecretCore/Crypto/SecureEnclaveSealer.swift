import CryptoKit
import Foundation
import LocalAuthentication

/// The production master key: a P-256 key generated inside the Secure
/// Enclave with a `userPresence` access control, so every `open` is gated by
/// Touch ID (or the login password) by the enclave itself — not by any
/// check this app could forget to make (plan §3.2 D4/D5, verified in
/// Phase 0). The key never leaves the chip; `keyBlob` is the opaque handle
/// the app keeps in the login Keychain.
///
/// An actor so the cached `LAContext` (which is what turns "one Touch ID
/// per field" into "one Touch ID per short session") has exactly one owner.
public actor SecureEnclaveSealer: SecretSealing {
    /// `LAContext` isn't `Sendable`, but the Security framework uses it from
    /// its own threads anyway; this app only ever hands it to one
    /// `SecureEnclave` key initialiser at a time, from inside this actor.
    private final class AuthContextBox: @unchecked Sendable {
        let context: LAContext
        init(_ context: LAContext) { self.context = context }
    }

    public struct Configuration: Sendable {
        /// How long one successful Touch ID keeps serving further `open`
        /// calls. macOS caps this at `LATouchIDAuthenticationMaximumAllowableReuseDuration` (5 min).
        public var reuseDuration: TimeInterval
        /// Shown in the system prompt.
        public var localizedReason: String

        public init(reuseDuration: TimeInterval = 30, localizedReason: String = "unlock your vault") {
            self.reuseDuration = reuseDuration
            self.localizedReason = localizedReason
        }
    }

    private let keyBlob: Data
    private let publicKey: P256.KeyAgreement.PublicKey
    private var authContext: AuthContextBox?
    /// When the user last answered a prompt through `authContext`. An
    /// evaluated `LAContext` keeps satisfying the key's `userPresence` check
    /// until it is invalidated — the reuse duration on the context does not
    /// expire that — so the window is enforced here, not by the framework.
    private var lastAuthenticatedAt: Date?
    public var configuration: Configuration

    public init(keyBlob: Data, configuration: Configuration = Configuration()) throws {
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keyBlob)
        self.keyBlob = keyBlob
        publicKey = key.publicKey
        self.configuration = configuration
    }

    /// Generates a fresh enclave key and returns the blob to store. Called
    /// once per install, by `loadOrCreateKeyBlob`.
    ///
    /// `.userPresence`, not `.biometryCurrentSet`: the latter makes the key
    /// permanently unusable the moment a fingerprint is added or removed,
    /// which for a personal vault is data loss, not security (plan D5).
    static func createKeyBlob() throws -> Data {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: accessControl).dataRepresentation
    }

    /// First launch creates the key; every launch after that loads it.
    public static func loadOrCreateKeyBlob(keychain: any KeychainStoring) throws -> Data {
        if let blob = try keychain.readMasterKeyBlob() { return blob }
        let blob = try createKeyBlob()
        try keychain.writeMasterKeyBlob(blob)
        return blob
    }

    public var isAvailable: Bool { SecureEnclave.isAvailable }

    public func seal(_ plaintext: Data, info: Data) throws -> SealedSecret {
        try HPKEEnvelope.seal(plaintext, to: publicKey, info: info)
    }

    public func open(_ sealed: SealedSecret, info: Data) async throws -> Data {
        if authContext != nil,
           Self.needsFreshAuthentication(lastAuthenticatedAt: lastAuthenticatedAt, reuseDuration: configuration.reuseDuration) {
            endAuthenticationSession()
        }
        let prompts = authContext == nil
        let box = authContext ?? makeAuthContext()
        authContext = box
        let keyBlob = keyBlob
        // Detached: the enclave blocks the calling thread until the user
        // answers the prompt, and that must not be this actor (other vault
        // calls keep flowing) nor the main thread (the window keeps painting).
        let plaintext = try await Task.detached {
            let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(
                dataRepresentation: keyBlob, authenticationContext: box.context
            )
            return try HPKEEnvelope.open(sealed, with: key, info: info)
        }.value
        if prompts { lastAuthenticatedAt = Date() }
        return plaintext
    }

    /// True once the last prompt is older than the reuse window; a window of
    /// 0 means every `open` prompts.
    static func needsFreshAuthentication(lastAuthenticatedAt: Date?, reuseDuration: TimeInterval, now: Date = Date()) -> Bool {
        guard reuseDuration > 0, let last = lastAuthenticatedAt else { return true }
        return now.timeIntervalSince(last) > reuseDuration
    }

    public func beginAuthenticationSession() async throws {
        let box = makeAuthContext()
        // The same context then backs `open`, whose enclave check is satisfied
        // by this evaluation for `configuration.reuseDuration`.
        guard try await box.context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: configuration.localizedReason) else {
            throw LAError(.authenticationFailed)
        }
        authContext?.context.invalidate()
        authContext = box
        lastAuthenticatedAt = Date()
    }

    public func endAuthenticationSession() {
        authContext?.context.invalidate()
        authContext = nil
        lastAuthenticatedAt = nil
    }

    /// Checked on every `open`, so a change applies immediately.
    public func setReuseDuration(_ seconds: TimeInterval) {
        configuration.reuseDuration = seconds
    }

    private func makeAuthContext() -> AuthContextBox {
        let context = LAContext()
        context.localizedReason = configuration.localizedReason
        context.touchIDAuthenticationAllowableReuseDuration = configuration.reuseDuration
        return AuthContextBox(context)
    }
}
