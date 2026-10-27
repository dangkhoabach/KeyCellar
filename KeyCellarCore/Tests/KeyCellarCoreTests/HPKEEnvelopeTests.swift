import CryptoKit
import Foundation
import Testing
@testable import KeyCellarCore

@Suite struct HPKEEnvelopeTests {
    private let key = P256.KeyAgreement.PrivateKey()

    @Test func sealOpenRoundTrip() throws {
        let info = HPKEEnvelope.info(blobId: "id-1")
        let sealed = try HPKEEnvelope.seal(Data("hello".utf8), to: key.publicKey, info: info)
        #expect(sealed.ciphertext != Data("hello".utf8))
        #expect(try HPKEEnvelope.open(sealed, with: key, info: info) == Data("hello".utf8))
    }

    @Test func wrongInfoFails() throws {
        let sealed = try HPKEEnvelope.seal(Data("x".utf8), to: key.publicKey, info: HPKEEnvelope.info(blobId: "a"))
        #expect(throws: (any Error).self) {
            _ = try HPKEEnvelope.open(sealed, with: key, info: HPKEEnvelope.info(blobId: "b"))
        }
    }

    @Test func tamperedCiphertextFails() throws {
        let info = HPKEEnvelope.info(blobId: "a")
        let sealed = try HPKEEnvelope.seal(Data("x".utf8), to: key.publicKey, info: info)
        var bytes = sealed.ciphertext
        bytes[bytes.count - 1] ^= 0x01
        let tampered = SealedSecret(encapsulatedKey: sealed.encapsulatedKey, ciphertext: bytes)
        #expect(throws: (any Error).self) { _ = try HPKEEnvelope.open(tampered, with: key, info: info) }
    }

    @Test func wrongKeyFails() throws {
        let info = HPKEEnvelope.info(blobId: "a")
        let sealed = try HPKEEnvelope.seal(Data("x".utf8), to: key.publicKey, info: info)
        #expect(throws: (any Error).self) {
            _ = try HPKEEnvelope.open(sealed, with: P256.KeyAgreement.PrivateKey(), info: info)
        }
    }

    @Test func eachSealIsUnique() throws {
        let info = HPKEEnvelope.info(blobId: "a")
        let one = try HPKEEnvelope.seal(Data("x".utf8), to: key.publicKey, info: info)
        let two = try HPKEEnvelope.seal(Data("x".utf8), to: key.publicKey, info: info)
        #expect(one != two, "fresh ephemeral key per seal — equal plaintexts must not produce equal blobs")
    }

    @Test func reuseWindowDecidesWhenToPromptAgain() {
        let now = Date()
        #expect(SecureEnclaveSealer.needsFreshAuthentication(lastAuthenticatedAt: nil, reuseDuration: 30, now: now))
        #expect(SecureEnclaveSealer.needsFreshAuthentication(lastAuthenticatedAt: now, reuseDuration: 0, now: now), "0 = every reveal asks")
        #expect(!SecureEnclaveSealer.needsFreshAuthentication(lastAuthenticatedAt: now.addingTimeInterval(-10), reuseDuration: 30, now: now))
        #expect(SecureEnclaveSealer.needsFreshAuthentication(lastAuthenticatedAt: now.addingTimeInterval(-31), reuseDuration: 30, now: now))
    }

    @Test func secureEnclaveKeyBlobIsCreatedOnceAndReloadable() throws {
        // No Secure Enclave on CI runners; Touch ID would be needed to open,
        // so this only covers create + persist + reload.
        guard SecureEnclave.isAvailable else { return }
        let keychain = InMemoryKeychainStore()
        let blob = try SecureEnclaveSealer.loadOrCreateKeyBlob(keychain: keychain)
        let again = try SecureEnclaveSealer.loadOrCreateKeyBlob(keychain: keychain)
        #expect(blob == again)
        #expect(keychain.writes == 1)
        _ = try SecureEnclaveSealer(keyBlob: blob)
    }
}
