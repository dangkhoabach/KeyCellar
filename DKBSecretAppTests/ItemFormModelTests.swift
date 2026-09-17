import DKBSecretCore
import Foundation
import Testing
@testable import DKB_Secret

@MainActor
@Suite struct ItemFormModelTests {
    @MainActor private struct Env {
        let database: AppDatabase
        let vault: SecretVault
        let items: ItemRepository
        let projects: ProjectRepository

        init() throws {
            database = try AppDatabase.inMemory()
            vault = SecretVault(database: database, sealer: SoftwareSealer())
            items = ItemRepository(dbQueue: database.dbQueue)
            projects = ProjectRepository(dbQueue: database.dbQueue)
        }

        func form(_ mode: ItemFormModel.Mode) -> ItemFormModel {
            ItemFormModel(mode: mode, vault: vault, items: items, projects: projects)
        }
    }

    @Test func validationRequiresKindTitleAndPrimarySecret() throws {
        let env = try Env()
        let form = env.form(.create(kind: nil))
        #expect(form.validate() == "Choose a kind.")
        form.kind = .apiKey
        #expect(form.validate() == "A title is required.")
        form.title = "x"
        #expect(form.validate() == "Key is required.")
        form.values["key"] = "abc"
        #expect(form.validate() == nil)
    }

    @Test func createSavesMetadataTagsProjectAndSealedSecrets() async throws {
        let env = try Env()
        let form = env.form(.create(kind: .login))
        form.title = " Router "
        form.values["url"] = "https://192.168.1.1"
        form.values["username"] = "admin"
        form.values["password"] = "hunter2"
        form.values["notes"] = "top shelf"
        form.tagsText = "home, infra"
        form.newProjectName = "Home"
        form.environment = .prod
        form.favorite = true
        form.expiryPreset = .days90
        #expect(await form.save())

        let item = try #require(try env.items.fetch(ItemQuery()).first)
        #expect(item.title == "Router")
        #expect(item.username == "admin")
        #expect(item.environment == .prod)
        #expect(item.favorite)
        #expect(item.projectId == (try env.projects.all().first?.id))
        #expect(try env.items.tags(for: item.id).map(\.name) == ["home", "infra"])
        let days = Calendar.current.dateComponents([.day], from: .now, to: try #require(item.expiresAt)).day
        #expect(days == 89 || days == 90)
        #expect(try await env.vault.reveal(itemId: item.id, field: "password").string == "hunter2")
        #expect(try await env.vault.reveal(itemId: item.id, field: "notes").string == "top shelf")
    }

    @Test func prefillFromClipboardDetection() throws {
        let env = try Env()
        let form = env.form(.create(kind: nil))
        form.prefill(from: "  re_abc123\n", detection: .init(kind: .apiKey, service: "Resend"))
        #expect(form.kind == .apiKey)
        #expect(form.values["key"] == "re_abc123")
        #expect(form.values["service"] == "Resend")
        #expect(form.title == "Resend")
    }

    @Test func envSetCreateThenEditAppliesOnlyTheDiff() async throws {
        let env = try Env()
        let create = env.form(.create(kind: .envSet))
        create.title = "Northwind prod"
        create.envText = "DATABASE_URL=postgres://a\nRESEND_API_KEY=re_1\nPORT=3000"
        #expect(await create.save())
        let item = try #require(try env.items.fetch(ItemQuery()).first)
        #expect(try env.items.blobs(for: item.id).map(\.field).sorted() == ["env.DATABASE_URL", "env.PORT", "env.RESEND_API_KEY"])

        let edit = env.form(.edit(item))
        await edit.loadForEditing()
        #expect(edit.envText.contains("RESEND_API_KEY=re_1"))
        edit.envText = "DATABASE_URL=postgres://a\nRESEND_API_KEY=re_2"
        #expect(await edit.save())
        let fields = try env.items.blobs(for: item.id).map(\.field).sorted()
        #expect(fields == ["env.DATABASE_URL", "env.RESEND_API_KEY"], "PORT removed")
        #expect(try await env.vault.reveal(itemId: item.id, field: "env.RESEND_API_KEY").string == "re_2")
    }

    @Test func editWithEmptySecretKeepsTheCurrentValue() async throws {
        let env = try Env()
        let create = env.form(.create(kind: .apiKey))
        create.title = "k"
        create.values["key"] = "original"
        #expect(await create.save())
        let item = try #require(try env.items.fetch(ItemQuery()).first)

        let edit = env.form(.edit(item))
        #expect(edit.title == "k")
        #expect(edit.values["key"] == nil, "secrets are never pre-filled into the form")
        edit.title = "renamed"
        #expect(await edit.save())
        #expect(try env.items.fetch(id: item.id)?.title == "renamed")
        #expect(try await env.vault.reveal(itemId: item.id, field: "key").string == "original")
    }
}
