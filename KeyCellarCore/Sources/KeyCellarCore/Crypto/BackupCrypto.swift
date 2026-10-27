import CommonCrypto
import CryptoKit
import Foundation

public enum BackupError: Error, Equatable {
    case notABackupFile
    case unsupportedVersion(Int)
    case wrongPassphraseOrCorrupt
    case passphraseTooShort
}

/// The `.dkbsecret` container. Layout:
///
///     [4 bytes big-endian header length][header JSON][AES-GCM combined box]
///
/// The header (format, version, KDF parameters, salt, date, item count) is
/// plaintext so a file can be identified without the passphrase, and it is
/// the GCM additional data, so editing it fails the tag check. The key is
/// PBKDF2-HMAC-SHA256 over the passphrase — CommonCrypto, no third-party
/// KDF; the version field is what lets a later format switch KDFs and still
/// read v1 files.
public enum BackupCrypto {
    public struct Header: Codable, Equatable, Sendable {
        public var format = "dkbsecret"
        public var version = 1
        public var kdf = "pbkdf2-sha256"
        public var iterations: Int
        public var salt: Data
        public var createdAt: Date
        public var itemCount: Int
    }

    public static let iterations = 600_000
    public static let minimumPassphraseLength = 12
    static let magic = "dkbsecret"

    public static func encrypt(_ plaintext: Data, passphrase: String, itemCount: Int, createdAt: Date = Date()) throws -> Data {
        guard passphrase.count >= minimumPassphraseLength else { throw BackupError.passphraseTooShort }
        var salt = Data(count: 32)
        salt.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let header = Header(iterations: iterations, salt: salt, createdAt: createdAt, itemCount: itemCount)
        return try encrypt(plaintext, passphrase: passphrase, header: header, nonce: AES.GCM.Nonce())
    }

    /// Deterministic variant for the fixed-vector test; production always
    /// takes the random path above.
    static func encrypt(_ plaintext: Data, passphrase: String, header: Header, nonce: AES.GCM.Nonce) throws -> Data {
        let headerData = try encoder.encode(header)
        let key = try deriveKey(passphrase: passphrase, salt: header.salt, iterations: header.iterations)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: headerData)
        var out = Data()
        var length = UInt32(headerData.count).bigEndian
        out.append(Data(bytes: &length, count: 4))
        out.append(headerData)
        out.append(box.combined!)
        return out
    }

    public static func readHeader(_ file: Data) throws -> Header {
        guard file.count > 4 else { throw BackupError.notABackupFile }
        let length = Int(UInt32(bigEndian: file.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        guard length > 0, file.count >= 4 + length,
              let header = try? decoder.decode(Header.self, from: file.subdata(in: 4..<(4 + length))),
              header.format == magic
        else { throw BackupError.notABackupFile }
        guard header.version == 1, header.kdf == "pbkdf2-sha256" else { throw BackupError.unsupportedVersion(header.version) }
        return header
    }

    public static func decrypt(_ file: Data, passphrase: String) throws -> Data {
        let header = try readHeader(file)
        let length = Int(UInt32(bigEndian: file.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        let headerData = file.subdata(in: 4..<(4 + length))
        let body = file.subdata(in: (4 + length)..<file.count)
        let key = try deriveKey(passphrase: passphrase, salt: header.salt, iterations: header.iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: body)
            return try AES.GCM.open(box, using: key, authenticating: headerData)
        } catch {
            throw BackupError.wrongPassphraseOrCorrupt
        }
    }

    static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let password = Array(passphrase.utf8)
        let status = salt.withUnsafeBytes { saltPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), password.map { CChar(bitPattern: $0) }, password.count,
                saltPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw BackupError.wrongPassphraseOrCorrupt }
        defer { _ = memset_s(&derived, derived.count, 0, derived.count) }
        return SymmetricKey(data: derived)
    }

    /// Fixed key ordering and date format so the header bytes — the GCM
    /// additional data — are reproducible.
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
