import CryptoKit
import Foundation

/// Where the master key lives is the one thing that differs between the app
/// (Secure Enclave) and the test suite (a software key): everything above
/// this protocol — `SecretVault`, the exporter, the UI — is the same code.
public protocol SecretSealing: Sendable {
    /// Needs only the public key, so it never asks for Touch ID.
    func seal(_ plaintext: Data, info: Data) async throws -> SealedSecret
    /// Goes through the private key. With the Secure Enclave that is where
    /// the Touch ID / login-password prompt comes from.
    func open(_ sealed: SealedSecret, info: Data) async throws -> Data
    /// Authenticates the user now (Touch ID or login password) and keeps
    /// that authentication for the following `open` calls, within the
    /// sealer's reuse window — so unlocking the vault and copying the first
    /// secret is one prompt, not two. Throws if the user cancels or fails.
    func beginAuthenticationSession() async throws
    /// Forgets any cached authentication so the next `open` prompts again —
    /// called when the vault locks.
    func endAuthenticationSession() async
}

/// Software P-256 master key. For tests and previews only: the key is in
/// process memory, which is exactly what the Secure Enclave design avoids.
public struct SoftwareSealer: SecretSealing {
    private let privateKey: P256.KeyAgreement.PrivateKey

    public init(privateKey: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey()) {
        self.privateKey = privateKey
    }

    public func seal(_ plaintext: Data, info: Data) throws -> SealedSecret {
        try HPKEEnvelope.seal(plaintext, to: privateKey.publicKey, info: info)
    }

    public func open(_ sealed: SealedSecret, info: Data) throws -> Data {
        try HPKEEnvelope.open(sealed, with: privateKey, info: info)
    }

    public func beginAuthenticationSession() {}

    public func endAuthenticationSession() {}
}
