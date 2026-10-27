import KeyCellarCore
import Foundation
import Testing
@testable import KeyCellar

@MainActor
@Suite struct ItemListViewModelTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func followsTheSidebarSelectionSearchAndFilter() async throws {
        let database = try AppDatabase.inMemory()
        let vault = SecretVault(database: database, sealer: SoftwareSealer())
        try await vault.create(SecretItem(kind: .apiKey, title: "Resend", environment: .prod), secrets: ["key": SecretBytes("a")])
        try await vault.create(SecretItem(kind: .login, title: "Router", environment: .dev), secrets: ["password": SecretBytes("b")])

        let model = ItemListViewModel(repository: ItemRepository(dbQueue: database.dbQueue), dbQueue: database.dbQueue)
        model.show(.section(.all))
        await waitUntil { model.items.map(\.title) == ["Resend", "Router"] }
        #expect(model.items.map(\.title) == ["Resend", "Router"])

        model.show(.kind(.login))
        await waitUntil { model.items.map(\.title) == ["Router"] }
        #expect(model.items.map(\.title) == ["Router"])

        model.show(.section(.all))
        model.search = "res"
        await waitUntil { model.items.map(\.title) == ["Resend"] }
        #expect(model.items.map(\.title) == ["Resend"])

        model.search = ""
        model.environmentFilter = .dev
        await waitUntil { model.items.map(\.title) == ["Router"] }
        #expect(model.items.map(\.title) == ["Router"])

        // A change in the database shows up without any refresh call.
        try await vault.create(SecretItem(kind: .login, title: "NAS", environment: .dev), secrets: ["password": SecretBytes("c")])
        await waitUntil { model.items.map(\.title) == ["NAS", "Router"] }
        #expect(model.items.map(\.title) == ["NAS", "Router"])
    }
}
