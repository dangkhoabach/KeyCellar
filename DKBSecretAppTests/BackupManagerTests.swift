import Testing
@testable import DKB_Secret

@Suite struct BackupManagerTests {
    @Test func prunesOnlyOurOldestFiles() {
        let names = [
            "DKB Secret Backup 2026-09-01 10-00.dkbsecret",
            "DKB Secret Backup 2026-09-03 10-00.dkbsecret",
            "DKB Secret Backup 2026-09-02 10-00.dkbsecret",
            "holiday.jpg",
            "DKB Secret Backup 2026-09-04 10-00.dkbsecret",
            "my-own-export.dkbsecret",
        ]
        #expect(BackupManager.filesToPrune(names, keep: 2) == [
            "DKB Secret Backup 2026-09-01 10-00.dkbsecret",
            "DKB Secret Backup 2026-09-02 10-00.dkbsecret",
        ])
        #expect(BackupManager.filesToPrune(names, keep: 10).isEmpty)
    }

    @Test func fileNamesSortChronologically() {
        let a = BackupManager.fileName(for: .init(timeIntervalSince1970: 1_700_000_000))
        let b = BackupManager.fileName(for: .init(timeIntervalSince1970: 1_700_090_000))
        #expect(a < b)
        #expect(a.hasSuffix(".dkbsecret"))
    }

    @Test func passphraseStrengthGrowsWithLengthAndVariety() {
        #expect(PassphraseSheet.entropyBits("") == 0)
        #expect(PassphraseSheet.entropyBits("aaaaaaaaaaaa") < PassphraseSheet.entropyBits("aAaAaAaAaAaA"))
        #expect(PassphraseSheet.entropyBits("aAaAaAaAaAaA") < PassphraseSheet.entropyBits("aA1!aA1!aA1!aA1!"))
        // Twelve lowercase letters pass the length rule but not the strength floor.
        #expect(PassphraseSheet.entropyBits("aaaaaaaaaaaa") < PassphraseSheet.minimumBits)
        #expect(PassphraseSheet.entropyBits("correct horse battery staple") >= PassphraseSheet.minimumBits)
    }
}
