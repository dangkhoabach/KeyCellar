import Foundation
import Testing
@testable import KeyCellarCore

@Suite struct SecretBytesTests {
    @Test func holdsAndExposesTheBytes() {
        let s = SecretBytes("héllo")
        #expect(s.count == 6)
        #expect(s.string == "héllo")
        #expect(s.data == Data("héllo".utf8))
        #expect(s.withUnsafeBytes { $0.count } == 6)
    }

    @Test func equalityIsByContent() {
        #expect(SecretBytes("a").isEqual(to: SecretBytes("a")))
        #expect(!SecretBytes("a").isEqual(to: SecretBytes("b")))
        #expect(!SecretBytes("a").isEqual(to: SecretBytes("aa")))
    }

    @Test func wipeZeroesTheBufferInPlace() {
        let s = SecretBytes("sensitive")
        s.wipe()
        #expect(s.withUnsafeBytes { $0.allSatisfy { $0 == 0 } })
        #expect(s.count == 9)
    }

    @Test func emptyValueIsFine() {
        let s = SecretBytes(Data())
        s.wipe()
        #expect(s.count == 0)
        #expect(s.string == "")
    }
}
