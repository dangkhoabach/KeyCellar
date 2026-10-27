import Foundation
import Testing
@testable import KeyCellarCore

/// Fixtures are made up in each provider's shape; none is a real code.
@Suite struct RecoveryCodesTests {
    private func values(_ text: String) -> [String] { RecoveryCodes.parse(text).map(\.value) }

    @Test func githubStyleSixteenLines() {
        let codes = (1...16).map { String(format: "a%03dc-%05d", $0, $0 * 7) }
        #expect(values(codes.joined(separator: "\n")) == codes)
    }

    @Test func googleStyleFileWithHeadingNumberingTwoColumnsAndFooter() {
        let text = """
            SAVE YOUR BACKUP CODES
            Keep these backup codes somewhere safe but accessible.

            1. 1111 2222\t\t2. 3333 4444
            3. 5555 6666\t\t4. 7777 8888
            5. 9999 0000\t\t6. 1212 3434
            7. 5656 7878\t\t8. 9090 1313
            9. 2424 3535\t\t10. 4646 5757

            (someone.test@gmail.com)

            * You can only use each backup code once.
            * Need more backup codes? Generate new codes at https://g.co/2sv
            * Generated on: Sep 28, 2026
            """
        #expect(values(text) == ["1111 2222", "3333 4444", "5555 6666", "7777 8888", "9999 0000",
                                 "1212 3434", "5656 7878", "9090 1313", "2424 3535", "4646 5757"])
        #expect(RecoveryCodes.accountHint(text) == "someone.test@gmail.com")
        #expect(RecoveryCodes.looksLikeCodeList(text))
    }

    @Test func columnsSeparatedBySpacesSplitOnlyWhenEveryColumnIsACode() {
        #expect(values("abcd-efgh    ijkl-mnop") == ["abcd-efgh", "ijkl-mnop"])
        #expect(values("1234  5678") == ["1234 5678"], "a double space inside one code")
    }

    @Test(arguments: [
        ("abcd-efgh", "Discord"),
        ("ABCDE-FGHIJ-KLMNO-PQRST-UVWXY", "Microsoft"),
        ("12345678", "eight digits"),
        ("a1b2c3d4e5f6", "one alphanumeric group"),
    ])
    func providerShapesAreCodes(code: String, provider: String) {
        #expect(values(code) == [code], "\(provider)")
    }

    @Test(arguments: [
        "SAVE YOUR BACKUP CODES", "KEEP THEM SAFE", "recovery-codes", "2026-09-28",
        "Page 1", "Room 12345678", "abcdefgh", "abc", "someone@gmail.com", "https://github.com/settings/security", "Tài khoản 12345678",
    ])
    func proseAndOtherLinesAreNotCodes(line: String) {
        #expect(values(line).isEmpty)
    }

    @Test func usedAndUnusedMarks() {
        let text = """
            [x] 1111-2222
            ✓ 3333-4444
            5555-6666 (used)
            7777-8888 (đã dùng)
            ~~9999-0000~~
            [ ] 1212-3434
            - 5656-7878
            1. [x] 9090-1313
            """
        let codes = RecoveryCodes.parse(text)
        #expect(codes.map(\.used) == [true, true, true, true, true, false, false, true])
        #expect(codes.map(\.value) == ["1111-2222", "3333-4444", "5555-6666", "7777-8888", "9999-0000",
                                       "1212-3434", "5656-7878", "9090-1313"])
    }

    @Test func duplicatesAreDroppedAndTheListIsCapped() {
        #expect(values("1111-2222\n1111-2222\n3333-4444") == ["1111-2222", "3333-4444"])
        let many = (1...100).map { String(format: "%04d-%04d", $0, $0) }.joined(separator: "\n")
        #expect(RecoveryCodes.parse(many).count == RecoveryCodes.maxCount)
    }

    @Test func surroundingSpaceIsTrimmedAndCaseKept() {
        #expect(values("   AbCd-1234   ") == ["AbCd-1234"])
    }

    @Test func serializeThenParseRoundTrips() {
        let codes = [RecoveryCodes.Code("aaaa-1111"), .init("bbbb-2222", used: true), .init("1234 5678")]
        #expect(RecoveryCodes.serialize(codes) == "aaaa-1111\n[x] bbbb-2222\n1234 5678")
        #expect(RecoveryCodes.parse(RecoveryCodes.serialize(codes)) == codes)
    }

    @Test func looksLikeCodeListNeedsFourCodesMakingUpMostOfTheText() {
        #expect(RecoveryCodes.looksLikeCodeList("1111-2222\n3333-4444\n5555-6666\n7777-8888"))
        #expect(!RecoveryCodes.looksLikeCodeList("1111-2222\n3333-4444\n5555-6666"), "three is too few")
        let prose = "Meeting notes\nRoom 12345678\nCall 1111-2222\nBring 3333-4444\nand 5555-6666 and 7777-8888\n"
            + (1...6).map { "line of ordinary text number \($0)." }.joined(separator: "\n")
        #expect(!RecoveryCodes.looksLikeCodeList(prose))
    }

    @Test func accountHintIsNilWithoutAnEmail() {
        #expect(RecoveryCodes.accountHint("1111-2222\n3333-4444") == nil)
        #expect(RecoveryCodes.accountHint("contact @ support") == nil)
    }
}

@Suite struct RecoveryCodeUsageTests {
    private func day(_ string: String) throws -> Date {
        try Date(string, strategy: Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    @Test func countUsedAndRemainingRoundTripThroughMetadata() throws {
        var item = makeItem("GitHub", kind: .recoveryCodes)
        #expect(item.recoveryCodeCount == 0)
        #expect(item.usedRecoveryCodes.isEmpty)
        item.recoveryCodeCount = 10
        item.usedRecoveryCodes = [5: try day("2026-09-20"), 2: try day("2026-09-12")]
        #expect(item.metadata[SecretItem.usedRecoveryCodesKey] == "2:2026-09-12,5:2026-09-20")
        #expect(item.usedRecoveryCodes == [2: try day("2026-09-12"), 5: try day("2026-09-20")])
        #expect(item.remainingRecoveryCodes == 8)
        item.usedRecoveryCodes = [:]
        #expect(item.metadata[SecretItem.usedRecoveryCodesKey] == nil)
    }

    @Test func positionsOutsideTheSetDoNotCountAndGarbageIsIgnored() throws {
        var item = makeItem("x", kind: .recoveryCodes)
        item.recoveryCodeCount = 3
        item.metadata[SecretItem.usedRecoveryCodesKey] = "1:2026-09-12,9:2026-09-12,oops,2:notadate"
        #expect(Array(item.usedRecoveryCodes.keys).sorted() == [1, 9])
        #expect(item.remainingRecoveryCodes == 2)
    }

    @Test func setUsedRecoveryCodesWritesMetadataOnlyAndBumpsUpdatedAt() async throws {
        let t = try TestVault()
        var item = makeItem("GitHub", kind: .recoveryCodes)
        item.recoveryCodeCount = 2
        item.updatedAt = Date(timeIntervalSince1970: 0)
        try await t.vault.create(item, secrets: ["codes": SecretBytes("aaaa-1111\nbbbb-2222")])
        let blobsBefore = try t.items.blobs(for: item.id)

        try t.items.setUsedRecoveryCodes([1: Date()], itemId: item.id)
        let fetched = try #require(try t.items.fetch(id: item.id))
        #expect(Array(fetched.usedRecoveryCodes.keys) == [1])
        #expect(fetched.remainingRecoveryCodes == 1)
        #expect(fetched.updatedAt > item.updatedAt)
        #expect(try t.items.blobs(for: item.id) == blobsBefore)
        #expect(throws: VaultError.itemNotFound("missing")) { try t.items.setUsedRecoveryCodes([:], itemId: "missing") }
    }

    @Test func codesNeverLandInTheDatabase() async throws {
        let t = try TestVault()
        let canary = "CANARY-7e1d-4b2a"
        var item = makeItem("Google", kind: .recoveryCodes, username: "someone@gmail.com")
        item.recoveryCodeCount = 2
        try await t.vault.create(item, secrets: ["codes": SecretBytes("\(canary)-1111\n\(canary)-2222")])
        try t.items.setUsedRecoveryCodes([2: Date()], itemId: item.id)
        _ = try await t.vault.reveal(itemId: item.id, field: "codes")
        #expect(try t.database.dumpAllValues().range(of: Data(canary.utf8)) == nil)
    }

    @Test func backupKeepsTheSetAndItsUsage() async throws {
        let source = try TestVault()
        var item = makeItem("GitHub", kind: .recoveryCodes, service: "GitHub")
        item.recoveryCodeCount = 3
        item.usedRecoveryCodes = [2: try day("2026-09-12")]
        try await source.vault.create(item, secrets: ["codes": SecretBytes("aaaa-1111\nbbbb-2222\ncccc-3333")])
        let file = try await VaultBackup.export(vault: source.vault, passphrase: "a passphrase long enough")

        let target = try TestVault()
        try await VaultBackup.import(file, passphrase: "a passphrase long enough", mode: .merge, into: target.vault)
        let restored = try #require(try target.items.fetch(id: item.id))
        #expect(restored.kind == .recoveryCodes)
        #expect(restored.recoveryCodeCount == 3)
        #expect(restored.usedRecoveryCodes == [2: try day("2026-09-12")])
        #expect(try await target.vault.reveal(itemId: item.id, field: "codes").string == "aaaa-1111\nbbbb-2222\ncccc-3333")
    }

    @Test func templateAndDefaultExpiry() {
        let template = SecretKind.recoveryCodes.template
        #expect(template.primaryField?.key == "codes")
        #expect(template.secretFields.map(\.key) == ["codes", "notes"])
        #expect(ExpiryPolicy().expiryDate(for: .recoveryCodes) == nil)
    }
}
