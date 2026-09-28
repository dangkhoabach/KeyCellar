import Foundation

/// Guesses what a pasted string is, so "new from clipboard" can pre-fill the
/// kind and service. Pure function over well-known key prefixes; anything
/// unrecognised is left for the user to classify.
public enum SecretDetector {
    public struct Detection: Equatable, Sendable {
        public let kind: SecretKind
        public let service: String?

        public init(kind: SecretKind, service: String?) {
            self.kind = kind
            self.service = service
        }
    }

    private static let prefixes: [(prefix: String, service: String)] = [
        ("sk-proj-", "OpenAI"), ("sk-ant-", "Anthropic"), ("sk-", "OpenAI"),
        ("ghp_", "GitHub"), ("github_pat_", "GitHub"), ("gho_", "GitHub"),
        ("AKIA", "AWS"),
        ("re_", "Resend"),
        ("xoxb-", "Slack"), ("xoxp-", "Slack"),
        ("sk_live_", "Stripe"), ("sk_test_", "Stripe"), ("rk_live_", "Stripe"),
        ("SG.", "SendGrid"),
        ("glpat-", "GitLab"),
        ("npm_", "npm"),
        ("AIza", "Google"),
    ]

    public static func detect(_ text: String) -> Detection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("-----BEGIN"), trimmed.contains("PRIVATE KEY-----") {
            return Detection(kind: .sshKey, service: nil)
        }
        if looksLikeEnvFile(trimmed) {
            return Detection(kind: .envSet, service: nil)
        }
        // Codes never contain `=`, and one line is never a list, so this
        // can't take a `.env` file or a single pasted key.
        if RecoveryCodes.looksLikeCodeList(trimmed) {
            return Detection(kind: .recoveryCodes, service: nil)
        }
        if let match = prefixes.first(where: { trimmed.hasPrefix($0.prefix) }) {
            return Detection(kind: .apiKey, service: match.service)
        }
        return nil
    }

    /// Two or more `KEY=VALUE` lines (comments and blanks ignored) reads as a
    /// `.env` file; a single line is more likely one key pasted on its own.
    private static func looksLikeEnvFile(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.count >= 2 else { return false }
        return lines.allSatisfy { line in
            guard let eq = line.firstIndex(of: "=") else { return false }
            let key = line[..<eq].replacingOccurrences(of: "export ", with: "")
            return !key.isEmpty && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
        }
    }
}
