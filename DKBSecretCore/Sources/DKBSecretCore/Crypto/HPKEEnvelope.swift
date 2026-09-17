import CryptoKit
import Foundation

/// One sealed value: the HPKE encapsulated key plus the AES-GCM ciphertext.
/// Both columns of a `SecretBlob`, nothing else.
public struct SealedSecret: Equatable, Sendable {
    public let encapsulatedKey: Data
    public let ciphertext: Data

    public init(encapsulatedKey: Data, ciphertext: Data) {
        self.encapsulatedKey = encapsulatedKey
        self.ciphertext = ciphertext
    }
}

/// The only place HPKE is called (plan §3.2 D4). Sealing needs just the
/// recipient public key; opening is generic over the private key so the
/// Secure Enclave key and a software P-256 key (tests) run the same code.
///
/// `info` binds a ciphertext to its blob id: a blob copied onto another
/// row fails to open instead of decrypting under the wrong name (plan §2 T9).
enum HPKEEnvelope {
    static let ciphersuite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256

    static func info(blobId: String) -> Data {
        Data("dkb-secret.v1.\(blobId)".utf8)
    }

    static func seal(_ plaintext: Data, to recipient: P256.KeyAgreement.PublicKey, info: Data) throws -> SealedSecret {
        var sender = try HPKE.Sender(recipientKey: recipient, ciphersuite: ciphersuite, info: info)
        let ciphertext = try sender.seal(plaintext)
        return SealedSecret(encapsulatedKey: sender.encapsulatedKey, ciphertext: ciphertext)
    }

    static func open<Key: HPKEDiffieHellmanPrivateKey>(_ sealed: SealedSecret, with key: Key, info: Data) throws -> Data {
        var recipient = try HPKE.Recipient(
            privateKey: key, ciphersuite: ciphersuite, info: info, encapsulatedKey: sealed.encapsulatedKey
        )
        return try recipient.open(sealed.ciphertext)
    }
}
