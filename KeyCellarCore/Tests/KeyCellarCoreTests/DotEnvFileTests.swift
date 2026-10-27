import Testing
@testable import KeyCellarCore

@Suite struct DotEnvFileTests {
    @Test func parsesTheCommonShapes() {
        let text = """
        # database
        DATABASE_URL=postgres://u:p@h/db
        export RESEND_API_KEY = re_123
        EMPTY=
        QUOTED="hello world"
        SINGLE='keep #this'
        TRAILING=value # comment
        BAD KEY=x
        1NUM=x
        novalue
        """
        let pairs = DotEnvFile.parse(text)
        #expect(pairs.map(\.key) == ["DATABASE_URL", "RESEND_API_KEY", "EMPTY", "QUOTED", "SINGLE", "TRAILING"])
        #expect(pairs.map(\.value) == ["postgres://u:p@h/db", "re_123", "", "hello world", "keep #this", "value"])
    }

    @Test func doubleQuotedValuesMaySpanLinesAndEscape() {
        let text = "PEM=\"-----BEGIN\nline2\nEND-----\"\nNEXT=1\nESC=\"a \\\"b\\\" c\\nd\""
        let pairs = DotEnvFile.parse(text)
        #expect(pairs.map(\.key) == ["PEM", "NEXT", "ESC"])
        #expect(pairs[0].value == "-----BEGIN\nline2\nEND-----")
        #expect(pairs[2].value == "a \"b\" c\nd")
    }

    @Test func serializeRoundTrips() {
        let pairs: [DotEnvFile.Pair] = [
            ("PLAIN", "abc"), ("EMPTY", ""), ("SPACED", "a b"), ("HASH", "x #y"),
            ("MULTI", "l1\nl2"), ("QUOTE", "say \"hi\""),
        ]
        let text = DotEnvFile.serialize(pairs)
        #expect(text.contains("PLAIN=abc"))
        #expect(text.contains("HASH=\"x #y\""))
        let back = DotEnvFile.parse(text)
        #expect(back.map(\.key) == pairs.map(\.key))
        #expect(back.map(\.value) == pairs.map(\.value))
    }

    @Test func keyValidation() {
        #expect(DotEnvFile.isValidKey("A_1"))
        #expect(!DotEnvFile.isValidKey("1A"))
        #expect(!DotEnvFile.isValidKey("A-B"))
        #expect(!DotEnvFile.isValidKey(""))
    }
}
