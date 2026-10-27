import Testing
@testable import KeyCellarCore

@Suite struct PasswordGeneratorTests {
    @Test func respectsLengthAndContainsEveryEnabledClass() {
        for _ in 0..<50 {
            let p = PasswordGenerator.generate(.init(length: 12))
            #expect(p.count == 12)
            let hasLower = p.contains(where: \.isLowercase), hasUpper = p.contains(where: \.isUppercase)
            let hasDigit = p.contains(where: \.isNumber), hasSymbol = p.contains(where: { !$0.isLetter && !$0.isNumber })
            #expect(hasLower && hasUpper && hasDigit && hasSymbol)
        }
    }

    @Test func onlyUsesEnabledClasses() {
        let p = PasswordGenerator.generate(.init(length: 40, lowercase: false, uppercase: false, digits: true, symbols: false))
        let allDigits = p.allSatisfy(\.isNumber)
        #expect(allDigits)
    }

    @Test func excludeAmbiguousDropsTheLookalikes() {
        let p = PasswordGenerator.generate(.init(length: 64, symbols: false, excludeAmbiguous: true))
        let hasAmbiguous = p.contains(where: { "0O1lI|".contains($0) })
        #expect(!hasAmbiguous)
    }

    @Test func noClassesGivesEmptyAndEntropyZero() {
        let none = PasswordGenerator.Options(lowercase: false, uppercase: false, digits: false, symbols: false)
        #expect(PasswordGenerator.generate(none) == "")
        #expect(PasswordGenerator.entropyBits(none) == 0)
    }

    @Test func entropyGrowsWithLengthAndAlphabet() {
        let digitsOnly = PasswordGenerator.Options(length: 10, lowercase: false, uppercase: false, digits: true, symbols: false)
        #expect(abs(PasswordGenerator.entropyBits(digitsOnly) - 10 * 3.3219) < 0.01)
        #expect(PasswordGenerator.entropyBits(.init(length: 20)) > PasswordGenerator.entropyBits(.init(length: 10)))
    }
}
