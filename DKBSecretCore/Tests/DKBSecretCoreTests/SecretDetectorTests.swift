import Testing
@testable import DKBSecretCore

@Suite struct SecretDetectorTests {
    @Test(arguments: [
        ("sk-proj-abc", "OpenAI"), ("sk-ant-abc", "Anthropic"), ("sk-abc", "OpenAI"),
        ("ghp_abc", "GitHub"), ("github_pat_abc", "GitHub"),
        ("AKIAIOSFODNN7EXAMPLE", "AWS"), ("re_123", "Resend"), ("xoxb-1-2", "Slack"),
        ("sk_live_1", "Stripe"), ("sk_test_1", "Stripe"), ("SG.abc", "SendGrid"),
        ("glpat-abc", "GitLab"), ("npm_abc", "npm"), ("AIzaSy", "Google"),
    ])
    func knownPrefixesAreApiKeysWithAService(input: String, service: String) {
        #expect(SecretDetector.detect("  \(input)\n") == .init(kind: .apiKey, service: service))
    }

    @Test func pemPrivateKeyIsAnSshKey() {
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----"
        #expect(SecretDetector.detect(pem) == .init(kind: .sshKey, service: nil))
        #expect(SecretDetector.detect("-----BEGIN CERTIFICATE-----") == nil)
    }

    @Test func severalKeyValueLinesAreAnEnvSet() {
        let env = "# db\nexport DATABASE_URL=postgres://x\nRESEND_KEY=re_1\n\nPORT=3000"
        #expect(SecretDetector.detect(env) == .init(kind: .envSet, service: nil))
        #expect(SecretDetector.detect("PORT=3000") == nil, "one line is a key, not a file")
        #expect(SecretDetector.detect("a=1\nnot a line") == nil)
    }

    @Test func unknownAndEmptyInputAreNil() {
        #expect(SecretDetector.detect("") == nil)
        #expect(SecretDetector.detect("   ") == nil)
        #expect(SecretDetector.detect("hello world") == nil)
    }
}
