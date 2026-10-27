import Foundation
import Testing
@testable import KeyCellarCore

/// 2 000 items must stay instant to list and search.
@Suite struct PerformanceTests {
    @Test func twoThousandItemsSearchUnder50ms() async throws {
        let t = try TestVault()
        let services = ["Resend", "GitHub", "AWS", "Stripe", "Slack", "OpenAI", "Cloudflare", "Vercel"]
        try await t.database.dbQueue.write { db in
            for i in 0..<2_000 {
                let item = SecretItem(kind: SecretKind.allCases[i % 5], title: "\(services[i % 8]) key \(i)",
                                      service: services[i % 8], url: "https://example\(i % 50).com", username: "user\(i)")
                try item.insert(db)
                try SecretBlob(itemId: item.id, field: "key", encapsulatedKey: Data(repeating: 1, count: 65),
                               ciphertext: Data(repeating: 2, count: 48)).insert(db)
            }
        }
        var elapsed: [Double] = []
        for query in [ItemQuery(), ItemQuery(search: "stripe"), ItemQuery(scope: .kind(.login), search: "user19", sort: .lastUsed)] {
            let start = ContinuousClock.now
            let rows = try t.items.fetch(query)
            elapsed.append(Double((ContinuousClock.now - start).components.attoseconds) / 1e15)
            #expect(!rows.isEmpty)
        }
        let quick = ContinuousClock.now
        _ = QuickSearchRanker.rank(try t.items.fetch(ItemQuery(search: "key")), query: "key 1")
        elapsed.append(Double((ContinuousClock.now - quick).components.attoseconds) / 1e15)
        #expect(elapsed.allSatisfy { $0 < 50 }, "ms per query: \(elapsed.map { String(format: "%.1f", $0) })")
    }
}
