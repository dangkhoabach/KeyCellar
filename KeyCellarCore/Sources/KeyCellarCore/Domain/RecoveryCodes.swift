import Foundation

/// 2FA recovery codes as providers hand them out: a `.txt` download or text
/// copied off the screen. Google numbers its ten `1234 5678` codes and prints
/// them in two columns between a heading and a footer, GitHub lists sixteen
/// `xxxxx-xxxxx`, Discord `abcd-efgh`, Microsoft one 25-character code. One
/// parser serves pasting, file import, drag and drop and the clipboard
/// detector.
public enum RecoveryCodes {
    public struct Code: Equatable, Sendable {
        public var value: String
        public var used: Bool

        public init(_ value: String, used: Bool = false) {
            self.value = value
            self.used = used
        }
    }

    public static let maxCount = 64

    /// Codes in the order they appear, duplicates dropped, at most `maxCount`.
    /// A line is split into columns only when every column is a code, so a
    /// code with a double space inside still reads as one.
    public static func parse(_ text: String) -> [Code] {
        var codes: [Code] = []
        var seen = Set<String>()
        for line in text.components(separatedBy: .newlines) {
            let columns = line.components(separatedBy: "\t")
                .flatMap { $0.components(separatedBy: "  ") }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let split = columns.compactMap(code(from:))
            let found = columns.count > 1 && split.count == columns.count ? split : code(from: line).map { [$0] } ?? []
            for code in found where seen.insert(code.value).inserted {
                codes.append(code)
                if codes.count == maxCount { return codes }
            }
        }
        return codes
    }

    /// One code per line, used ones marked `[x] ` so `parse` reads the state back.
    public static func serialize(_ codes: [Code]) -> String {
        codes.map { ($0.used ? "[x] " : "") + $0.value }.joined(separator: "\n")
    }

    /// For the clipboard detector and file drops: at least four codes, and
    /// codes make up most of the text (a Google file has ten codes on five
    /// lines plus about six lines of heading, account and footer).
    public static func looksLikeCodeList(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let count = parse(text).count
        return count >= 4 && count * 2 >= lines.count
    }

    /// The account a Google file names ("(someone@gmail.com)"): the first
    /// word with an `@` and a dot after it.
    public static func accountHint(_ text: String) -> String? {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()<>,;:\"'")))
            .first { word in
                guard let at = word.firstIndex(of: "@"), at != word.startIndex else { return false }
                return word[word.index(after: at)...].contains(".")
            }?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    // MARK: One code

    private static let usedPrefixes = ["[x]", "[X]", "☑", "✓", "✔", "✅"]
    private static let unusedPrefixes = ["[ ]", "☐", "- ", "* ", "• "]
    private static let usedSuffixes = ["(used)", "(đã dùng)"]

    /// Strips numbering, bullets and used/unused marks in any order, then
    /// checks what is left is shaped like a code.
    static func code(from text: String) -> Code? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var used = false
        while true {
            if let prefix = usedPrefixes.first(where: { s.hasPrefix($0) }) {
                used = true
                s = String(s.dropFirst(prefix.count))
            } else if let prefix = unusedPrefixes.first(where: { s.hasPrefix($0) }) {
                s = String(s.dropFirst(prefix.count))
            } else if let rest = droppingOrdinal(s) {
                s = rest
            } else {
                break
            }
            s = s.trimmingCharacters(in: .whitespaces)
        }
        if let suffix = usedSuffixes.first(where: { s.lowercased().hasSuffix($0) }) {
            used = true
            s = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        if s.count > 4, s.hasPrefix("~~"), s.hasSuffix("~~") {
            used = true
            s = String(s.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
        }
        let value = s.split(separator: " ").joined(separator: " ")
        return isCode(value) ? Code(value, used: used) : nil
    }

    /// "1. " / "12) " — one or two digits, then `.` or `)`, then a space.
    private static func droppingOrdinal(_ s: String) -> String? {
        let digits = s.prefix(while: \.isASCIIDigit)
        guard (1...2).contains(digits.count) else { return nil }
        let rest = s.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        return String(rest.dropFirst(2))
    }

    /// ASCII letters and digits in 1–6 groups of one length (3–32), joined by
    /// one space or dash, 6–64 characters without separators, with a digit
    /// or a dash. Every provider above uses equal groups; prose rarely does,
    /// which keeps "Room 12345678", "KEEP THEM SAFE" and "recovery-codes" out.
    static func isCode(_ s: String) -> Bool {
        guard s.allSatisfy({ $0.isASCIIDigit || $0.isASCIILetter || $0 == " " || $0 == "-" }) else { return false }
        let groups = s.split(omittingEmptySubsequences: false, whereSeparator: { $0 == " " || $0 == "-" })
        guard (1...6).contains(groups.count), let size = groups.first?.count, (3...32).contains(size),
              groups.allSatisfy({ $0.count == size }), (6...64).contains(size * groups.count) else { return false }
        return s.contains(where: \.isASCIIDigit) || s.contains("-")
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}

// MARK: - Usage on the item

/// Which codes are used is metadata, not part of the sealed blob: ticking a
/// code or counting what is left needs no Touch ID. A stolen database shows
/// how many codes a set has and which positions are used, never a code.
extension SecretItem {
    public static let recoveryCodeCountKey = "codeCount"
    public static let usedRecoveryCodesKey = "usedCodes"

    public var recoveryCodeCount: Int {
        get { metadata[Self.recoveryCodeCountKey].flatMap(Int.init) ?? 0 }
        set { metadata[Self.recoveryCodeCountKey] = String(newValue) }
    }

    /// 1-based position in the set → the day it was marked used in the vault.
    /// Stored as `2:2026-09-12,5:2026-09-20`.
    public var usedRecoveryCodes: [Int: Date] {
        get {
            var used: [Int: Date] = [:]
            for entry in (metadata[Self.usedRecoveryCodesKey] ?? "").split(separator: ",") {
                let parts = entry.split(separator: ":")
                guard parts.count == 2, let index = Int(parts[0]),
                      let day = try? Date(String(parts[1]), strategy: Self.usedDayFormat) else { continue }
                used[index] = day
            }
            return used
        }
        set {
            metadata[Self.usedRecoveryCodesKey] = newValue.isEmpty ? nil : newValue.keys.sorted()
                .map { "\($0):\(newValue[$0]!.formatted(Self.usedDayFormat))" }
                .joined(separator: ",")
        }
    }

    public var remainingRecoveryCodes: Int {
        let count = recoveryCodeCount
        return count - usedRecoveryCodes.keys.filter { $0 >= 1 && $0 <= count }.count
    }

    /// Local calendar day: a code used late in the evening shows that day.
    private static var usedDayFormat: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: .current).year().month().day()
    }
}
