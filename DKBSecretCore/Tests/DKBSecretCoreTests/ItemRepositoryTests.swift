import Foundation
import Testing
@testable import DKBSecretCore

@Suite struct ItemRepositoryTests {
    private func seeded() async throws -> TestVault {
        let t = try TestVault()
        let project = try ProjectRepository(dbQueue: t.database.dbQueue).findOrCreate(name: "CaPheSuaDa")
        try await t.vault.create(makeItem("Resend production", service: "Resend", username: "ops@example.com",
                                          url: "https://resend.com", projectId: project.id, favorite: true),
                                 tags: ["email", "prod"], secrets: ["key": SecretBytes("re_1")])
        try await t.vault.create(makeItem("GitHub PAT", service: "GitHub"), tags: ["ci"], secrets: ["key": SecretBytes("ghp_1")])
        try await t.vault.create(makeItem("Router admin", kind: .login, username: "admin"), secrets: ["password": SecretBytes("x")])
        return t
    }

    @Test func insertedItemRoundTripsThroughTheRow() async throws {
        let t = try TestVault()
        var item = makeItem("Deploy key", kind: .sshKey, username: "root")
        item.metadata = ["host": "10.0.0.1", "publicKey": "ssh-ed25519 AAAA"]
        item.environment = .prod
        try await t.vault.create(item, secrets: ["privateKey": SecretBytes("pem")])
        let fetched = try t.items.fetch(id: item.id)
        #expect(fetched?.metadata == item.metadata)
        #expect(fetched?.environment == .prod)
        #expect(fetched?.kind == .sshKey)
    }

    @Test func searchMatchesTitleServiceUsernameUrlProjectAndTag() async throws {
        let t = try await seeded()
        for term in ["resend", "OPS@", "resend.com", "CaPhe", "email", "GitHub"] {
            let hits = try t.items.fetch(ItemQuery(search: term))
            #expect(!hits.isEmpty, "no hit for \(term)")
        }
        #expect(try t.items.fetch(ItemQuery(search: "re_1")).isEmpty, "secret values must never be searchable")
        #expect(try t.items.fetch(ItemQuery(search: "nothing-like-this")).isEmpty)
    }

    @Test func scopesFilterAsTheSidebarExpects() async throws {
        let t = try await seeded()
        let all = try t.items.fetch(ItemQuery(scope: .all))
        #expect(all.count == 3)
        #expect(try t.items.fetch(ItemQuery(scope: .favorites)).map(\.title) == ["Resend production"])
        #expect(try t.items.fetch(ItemQuery(scope: .kind(.login))).map(\.title) == ["Router admin"])
        let projectId = try #require(all.first { $0.title == "Resend production" }?.projectId)
        #expect(try t.items.fetch(ItemQuery(scope: .project(projectId))).count == 1)
        let ci = try #require(TagRepository(dbQueue: t.database.dbQueue).all().first { $0.name == "ci" })
        #expect(try t.items.fetch(ItemQuery(scope: .tag(ci.id))).map(\.title) == ["GitHub PAT"])
        #expect(try t.items.fetch(ItemQuery(scope: .recent)).isEmpty, "nothing revealed yet")
        #expect(try t.items.fetch(ItemQuery(scope: .trash)).isEmpty)
    }

    @Test func recentIsOrderedByLastReveal() async throws {
        let t = try await seeded()
        let all = try t.items.fetch(ItemQuery())
        let github = try #require(all.first { $0.title == "GitHub PAT" })
        let resend = try #require(all.first { $0.title == "Resend production" })
        _ = try await t.vault.reveal(itemId: resend.id, field: "key")
        try await Task.sleep(for: .milliseconds(5))
        _ = try await t.vault.reveal(itemId: github.id, field: "key")
        #expect(try t.items.fetch(ItemQuery(scope: .recent)).map(\.title) == ["GitHub PAT", "Resend production"])
    }

    @Test func expiringScopeUsesTheWindow() async throws {
        let t = try TestVault()
        let now = Date()
        try await t.vault.create(makeItem("soon", expiresAt: now.addingTimeInterval(3 * 86_400)), secrets: ["key": SecretBytes("a")])
        try await t.vault.create(makeItem("later", expiresAt: now.addingTimeInterval(60 * 86_400)), secrets: ["key": SecretBytes("b")])
        try await t.vault.create(makeItem("never"), secrets: ["key": SecretBytes("c")])
        #expect(try t.items.fetch(ItemQuery(scope: .expiring(withinDays: 14)), now: now).map(\.title) == ["soon"])
        #expect(try t.items.fetch(ItemQuery(sort: .expires), now: now).map(\.title) == ["soon", "later", "never"])
    }

    @Test func titleSortIsCaseInsensitive() async throws {
        let t = try TestVault()
        for title in ["beta", "Alpha", "gamma"] {
            try await t.vault.create(makeItem(title), secrets: ["key": SecretBytes("x")])
        }
        #expect(try t.items.fetch(ItemQuery(sort: .title)).map(\.title) == ["Alpha", "beta", "gamma"])
    }

    @Test func tagsAreDeduplicatedTrimmedAndReplacedOnUpdate() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, tags: [" prod", "prod", "", "email"], secrets: ["key": SecretBytes("x")])
        #expect(try t.items.tags(for: item.id).map(\.name) == ["email", "prod"])
        try await t.vault.updateMetadata(item, tags: ["ci"])
        #expect(try t.items.tags(for: item.id).map(\.name) == ["ci"])
        // The now-unused tags still exist as tags; only the links changed.
        #expect(try TagRepository(dbQueue: t.database.dbQueue).all().count == 3)
    }

    @Test func favoriteToggle() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, secrets: ["key": SecretBytes("x")])
        try t.items.setFavorite(true, itemId: item.id)
        #expect(try t.items.fetch(id: item.id)?.favorite == true)
    }
}
