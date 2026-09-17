import DKBSecretCore
import Foundation
import GRDB
import Observation

/// The middle column: the items for the current sidebar selection, search
/// text, sort and environment filter, re-fetched through a GRDB observation
/// whenever the query or the data changes.
@MainActor
@Observable
final class ItemListViewModel {
    var search = "" { didSet { restart() } }
    var sort: ItemQuery.Sort = .title { didSet { restart() } }
    var environmentFilter: DeploymentEnvironment? { didSet { restart() } }
    private(set) var items: [SecretItem] = []

    private var scope: ItemQuery.Scope = .all
    private let repository: ItemRepository
    private let dbQueue: DatabaseQueue
    private var task: Task<Void, Never>?

    init(repository: ItemRepository, dbQueue: DatabaseQueue) {
        self.repository = repository
        self.dbQueue = dbQueue
    }

    func show(_ selection: SidebarSelection) {
        scope = selection.scope
        restart()
    }

    var query: ItemQuery { ItemQuery(scope: scope, search: search, sort: sort) }

    private func restart() {
        task?.cancel()
        let observation = repository.observation(query)
        let filter = environmentFilter
        let dbQueue = dbQueue
        task = Task { [weak self] in
            do {
                for try await items in observation.values(in: dbQueue) {
                    guard let self else { return }
                    self.items = filter.map { env in items.filter { $0.environment == env } } ?? items
                }
            } catch {}
        }
    }
}
