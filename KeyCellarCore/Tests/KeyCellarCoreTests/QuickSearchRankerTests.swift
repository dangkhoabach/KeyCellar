import Foundation
import Testing
@testable import KeyCellarCore

@Suite struct QuickSearchRankerTests {
    private let items = [
        makeItem("Resend production", service: "Resend"),
        makeItem("CaPheSuaDa Resend", service: "Resend"),
        makeItem("GitHub token", service: "GitHub", username: "resend-bot"),
        makeItem("Stripe", url: "https://dashboard.stripe.com/resend"),
        makeItem("Unrelated"),
    ]

    @Test func prefixBeatsWordPrefixBeatsSubstringBeatsOtherFields() {
        let titles = QuickSearchRanker.rank(items, query: "res").map(\.title)
        #expect(titles == ["Resend production", "CaPheSuaDa Resend", "GitHub token", "Stripe"])
    }

    @Test func recentlyUsedWinsTiesAndEmptyQueryListsRecentFirst() {
        var recent = makeItem("Resend staging", service: "Resend")
        recent.lastUsedAt = Date()
        let all = items + [recent]
        #expect(QuickSearchRanker.rank(all, query: "resend").first?.title == "Resend staging")
        #expect(QuickSearchRanker.rank(all, query: "").first?.title == "Resend staging")
        #expect(QuickSearchRanker.rank(all, query: "", limit: 2).count == 2)
    }

    @Test func caseInsensitiveAndTrimmed() {
        #expect(QuickSearchRanker.rank(items, query: "  GITHUB ").map(\.title) == ["GitHub token"])
        #expect(QuickSearchRanker.rank(items, query: "zzz").isEmpty)
    }
}
