import Foundation

/// The `.env` dialect the form editor, drag-and-drop import and the `.env`
/// export all speak: `KEY=VALUE` lines, `#` comments, an optional `export `,
/// single- or double-quoted values (double quotes may span lines), and
/// everything else passed through as-is. Order is preserved.
public enum DotEnvFile {
    public typealias Pair = (key: String, value: String)

    public static func parse(_ text: String) -> [Pair] {
        var pairs: [Pair] = []
        var lines = text.components(separatedBy: .newlines)[...]
        while let raw = lines.popFirst() {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard isValidKey(key) else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            if value.hasPrefix("\"") {
                // Collect until the closing quote, across lines if needed.
                var body = String(value.dropFirst())
                while !hasClosingQuote(body) , let next = lines.popFirst() {
                    body += "\n" + next
                }
                if let close = body.lastIndex(of: "\"") { body = String(body[..<close]) }
                value = body.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"")
            } else if value.hasPrefix("'"), value.count >= 2, value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            } else if let hash = value.range(of: " #") {
                value = value[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            pairs.append((String(key), value))
        }
        return pairs
    }

    /// Quotes only when needed, so a round trip through `parse` is exact.
    public static func serialize(_ pairs: [Pair]) -> String {
        pairs.map { key, value in
            let needsQuotes = value.isEmpty == false && (value.contains("\n") || value.contains(" #") || value.contains("\"")
                || value.hasPrefix(" ") || value.hasSuffix(" ") || value.hasPrefix("'"))
            if needsQuotes {
                let escaped = value.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
                return "\(key)=\"\(escaped)\""
            }
            return "\(key)=\(value)"
        }.joined(separator: "\n")
    }

    public static func isValidKey(_ key: some StringProtocol) -> Bool {
        !key.isEmpty && !key.first!.isNumber && key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func hasClosingQuote(_ body: String) -> Bool {
        var escaped = false
        for c in body {
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if c == "\"" { return true }
        }
        return false
    }
}
