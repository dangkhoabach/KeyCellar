import Foundation

/// Orders search hits for the quick-search panel and the menu bar, where
/// only the first few rows are visible: a title that starts with the query
/// beats a word that starts with it, which beats a substring anywhere;
/// recently used items win ties.
public enum QuickSearchRanker {
    public static func rank(_ items: [SecretItem], query: String, limit: Int = 8) -> [SecretItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            return Array(items.sorted(by: recentFirst).prefix(limit))
        }
        return items
            .map { ($0, score($0, q)) }
            .filter { $0.1 > 0 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return recentFirst(a.0, b.0)
            }
            .prefix(limit)
            .map(\.0)
    }

    static func score(_ item: SecretItem, _ q: String) -> Int {
        let title = item.title.lowercased()
        if title.hasPrefix(q) { return 4 }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 3 }
        if title.contains(q) { return 2 }
        let others = [item.service, item.username, item.url].compactMap { $0?.lowercased() }
        if others.contains(where: { $0.contains(q) }) { return 1 }
        return 0
    }

    private static func recentFirst(_ a: SecretItem, _ b: SecretItem) -> Bool {
        switch (a.lastUsedAt, b.lastUsedAt) {
        case let (x?, y?) where x != y: return x > y
        case (.some, .none): return true
        case (.none, .some): return false
        default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
