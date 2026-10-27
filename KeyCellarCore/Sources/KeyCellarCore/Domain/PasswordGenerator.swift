import Foundation

/// Random passwords from the system CSPRNG. Every enabled character class is
/// guaranteed at least once so "must contain a digit" style rules pass.
public enum PasswordGenerator {
    public struct Options: Equatable, Sendable {
        public var length: Int
        public var lowercase: Bool
        public var uppercase: Bool
        public var digits: Bool
        public var symbols: Bool
        /// Drops 0/O/1/l/I/| — characters that get misread when typed by hand.
        public var excludeAmbiguous: Bool

        public init(length: Int = 20, lowercase: Bool = true, uppercase: Bool = true,
                    digits: Bool = true, symbols: Bool = true, excludeAmbiguous: Bool = false) {
            self.length = length
            self.lowercase = lowercase
            self.uppercase = uppercase
            self.digits = digits
            self.symbols = symbols
            self.excludeAmbiguous = excludeAmbiguous
        }

        var classes: [[Character]] {
            var result: [[Character]] = []
            if lowercase { result.append(Array("abcdefghijklmnopqrstuvwxyz")) }
            if uppercase { result.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
            if digits { result.append(Array("0123456789")) }
            if symbols { result.append(Array("!@#$%^&*()-_=+[]{};:,.<>?/~")) }
            if excludeAmbiguous {
                let ambiguous: Set<Character> = ["0", "O", "1", "l", "I", "|"]
                result = result.map { $0.filter { !ambiguous.contains($0) } }
            }
            return result.filter { !$0.isEmpty }
        }
    }

    public static let lengthRange = 8...64

    public static func generate(_ options: Options = Options()) -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(options, using: &rng)
    }

    static func generate<R: RandomNumberGenerator>(_ options: Options, using rng: inout R) -> String {
        let classes = options.classes
        let length = max(options.length, classes.count)
        guard !classes.isEmpty else { return "" }
        let alphabet = classes.flatMap { $0 }
        var chars = classes.map { $0.randomElement(using: &rng)! }
        while chars.count < length {
            chars.append(alphabet.randomElement(using: &rng)!)
        }
        chars.shuffle(using: &rng)
        return String(chars)
    }

    /// log2(alphabet size) × length — the usual strength figure.
    public static func entropyBits(_ options: Options) -> Double {
        let size = options.classes.reduce(0) { $0 + $1.count }
        guard size > 0 else { return 0 }
        return Double(options.length) * log2(Double(size))
    }
}
