import Testing
@testable import DKBSecretCore

@Suite struct ProjectTagSettingsTests {
    @Test func findOrCreateReturnsTheExistingProjectAndNumbersNewOnes() throws {
        let db = try AppDatabase.inMemory()
        let projects = ProjectRepository(dbQueue: db.dbQueue)
        let a = try projects.findOrCreate(name: "A")
        let again = try projects.findOrCreate(name: "A")
        let b = try projects.findOrCreate(name: "B")
        #expect(a.id == again.id)
        #expect(b.sortOrder == a.sortOrder + 1)
        #expect(try projects.all().map(\.name) == ["A", "B"])
    }

    @Test func projectAndTagNamesMatchCaseInsensitively() async throws {
        let t = try TestVault()
        let projects = ProjectRepository(dbQueue: t.database.dbQueue)
        #expect(try projects.findOrCreate(name: "Prod").id == projects.findOrCreate(name: "prod").id)
        try await t.vault.create(makeItem("a"), tags: ["Email"], secrets: ["key": SecretBytes("x")])
        try await t.vault.create(makeItem("b"), tags: ["email"], secrets: ["key": SecretBytes("x")])
        #expect(try TagRepository(dbQueue: t.database.dbQueue).all().map(\.name) == ["Email"])
    }

    @Test func deletingAProjectKeepsItsItems() async throws {
        let t = try TestVault()
        let projects = ProjectRepository(dbQueue: t.database.dbQueue)
        let p = try projects.findOrCreate(name: "P")
        let item = makeItem("x", projectId: p.id)
        try await t.vault.create(item, secrets: ["key": SecretBytes("x")])
        try projects.delete(id: p.id)
        #expect(try t.items.fetch(id: item.id)?.projectId == nil)
    }

    @Test func tagRenameAndDelete() async throws {
        let t = try TestVault()
        let item = makeItem("x")
        try await t.vault.create(item, tags: ["old"], secrets: ["key": SecretBytes("x")])
        let tags = TagRepository(dbQueue: t.database.dbQueue)
        let tag = try #require(try tags.all().first)
        try tags.rename(id: tag.id, to: "new")
        #expect(try t.items.tags(for: item.id).map(\.name) == ["new"])
        try tags.delete(id: tag.id)
        #expect(try t.items.tags(for: item.id).isEmpty)
    }

    @Test func settingsSetGetOverwriteAndClear() throws {
        let db = try AppDatabase.inMemory()
        let settings = SettingsRepository(dbQueue: db.dbQueue)
        #expect(try settings.get("k") == nil)
        try settings.set("k", "1")
        try settings.set("k", "2")
        #expect(try settings.get("k") == "2")
        try settings.set("k", nil)
        #expect(try settings.get("k") == nil)
    }
}
