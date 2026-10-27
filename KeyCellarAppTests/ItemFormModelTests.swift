import KeyCellarCore
import Foundation
import Testing
@testable import KeyCellar

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
        // Messages follow the in-app language, so compare through the same lookup.
        let bundle = AppLocale.bundle
        #expect(form.validate() == String(localized: "Choose a kind.", bundle: bundle))
        form.kind = .apiKey
        #expect(form.validate() == String(localized: "A title is required.", bundle: bundle))
        form.title = "x"
        let key = String(localized: "Key", bundle: bundle)
        #expect(form.validate() == String(localized: "\(key) is required.", bundle: bundle))
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

    // MARK: Recovery codes (fixtures are made up)

    private func createCodes(_ env: Env, _ text: String) async throws -> SecretItem {
        let form = env.form(.create(kind: .recoveryCodes))
        form.title = "GitHub"
        form.loadCodes(text)
        #expect(await form.save())
        return try #require(try env.items.fetch(ItemQuery()).first)
    }

    @Test func recoveryCodesCreateSealsTheNormalisedListAndCountsIt() async throws {
        let env = try Env()
        let text = "SAVE YOUR BACKUP CODES\n1. 1111 2222\t\t2. 3333 4444\n3. 5555 6666\t\t4. 7777 8888\n(someone.test@gmail.com)"
        let item = try await createCodes(env, text)
        #expect(item.kind == .recoveryCodes)
        #expect(item.username == "someone.test@gmail.com")
        #expect(item.recoveryCodeCount == 4)
        #expect(item.usedRecoveryCodes.isEmpty)
        #expect(try await env.vault.reveal(itemId: item.id, field: "codes").string == "1111 2222\n3333 4444\n5555 6666\n7777 8888")
    }

    @Test func recoveryCodesMarkedUsedWhenCreatedAreRecorded() async throws {
        let env = try Env()
        let item = try await createCodes(env, "aaaa-1111\n[x] bbbb-2222\ncccc-3333")
        #expect(Array(item.usedRecoveryCodes.keys) == [2])
        #expect(item.remainingRecoveryCodes == 2)
        #expect(try await env.vault.reveal(itemId: item.id, field: "codes").string == "aaaa-1111\nbbbb-2222\ncccc-3333")
    }

    @Test func recoveryCodesEditRemapsUsedCodesByValue() async throws {
        let env = try Env()
        let item = try await createCodes(env, "aaaa-1111\nbbbb-2222\n[x] cccc-3333")
        let usedOn = try #require(item.usedRecoveryCodes[3])

        let edit = env.form(.edit(item))
        await edit.loadForEditing()
        #expect(edit.values["codes"] == "aaaa-1111\nbbbb-2222\n[x] cccc-3333")
        edit.values["codes"] = "aaaa-1111\n[x] cccc-3333\n[x] dddd-4444"
        #expect(await edit.save())

        let saved = try #require(try env.items.fetch(id: item.id))
        #expect(saved.recoveryCodeCount == 3)
        #expect(saved.usedRecoveryCodes[2] == usedOn, "cccc moved from 3 to 2 and keeps its date")
        #expect(saved.usedRecoveryCodes[3] != nil)
        #expect(saved.usedRecoveryCodes[1] == nil)
        #expect(try await env.vault.reveal(itemId: item.id, field: "codes").string == "aaaa-1111\ncccc-3333\ndddd-4444")
    }

    @Test func recoveryCodesEditWithoutChangesKeepsTheBlob() async throws {
        let env = try Env()
        let item = try await createCodes(env, "aaaa-1111\nbbbb-2222")
        let blobs = try env.items.blobs(for: item.id)
        let edit = env.form(.edit(item))
        await edit.loadForEditing()
        edit.title = "renamed"
        #expect(await edit.save())
        #expect(try env.items.blobs(for: item.id) == blobs)
    }

    @Test func replacingCodesStartsEmptyAndResetsUsage() async throws {
        let env = try Env()
        let item = try await createCodes(env, "[x] aaaa-1111\nbbbb-2222")
        let replace = env.form(.edit(item))
        replace.replacingCodes = true
        await replace.loadForEditing()
        #expect((replace.values["codes"] ?? "").isEmpty, "the old set is not revealed")
        #expect(replace.validate() == String(localized: "Add at least one recovery code.", bundle: AppLocale.bundle))
        replace.values["codes"] = "eeee-5555\nffff-6666\ngggg-7777"
        #expect(await replace.save())

        let saved = try #require(try env.items.fetch(id: item.id))
        #expect(saved.recoveryCodeCount == 3)
        #expect(saved.usedRecoveryCodes.isEmpty)
        #expect(try await env.vault.reveal(itemId: item.id, field: "codes").string == "eeee-5555\nffff-6666\ngggg-7777")
        #expect(try env.items.blobs(for: item.id).filter { $0.field == "codes" }.map(\.slot) == [0], "no history for a dead set")
    }

    @Test func prefillFromClipboardCodeList() throws {
        let env = try Env()
        let form = env.form(.create(kind: nil))
        let text = "abcde-12345\nfghij-67890\nklmno-13579\npqrst-24680"
        form.prefill(from: text, detection: .init(kind: .recoveryCodes, service: nil))
        #expect(form.kind == .recoveryCodes)
        #expect(form.parsedCodes.count == 4)
        #expect(form.expiryPreset == .none)
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
