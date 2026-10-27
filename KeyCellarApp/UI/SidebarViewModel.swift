import KeyCellarCore
import Foundation
import GRDB
import Observation

/// Projects, tags and the per-row counts the sidebar shows. Everything comes
/// from GRDB observations, so a change anywhere (form save, trash, drag to a
/// project) is reflected without any manual refresh call.
@MainActor
@Observable
final class SidebarViewModel {
    private(set) var projects: [Project] = []
    private(set) var tags: [Tag] = []
    private(set) var counts = Counts()
    /// A rename that hit the UNIQUE name constraint, for the sidebar's alert.
    private(set) var lastError: String?

    struct Counts: Equatable {
        var all = 0, favorites = 0, expiring = 0, trash = 0
        var byKind: [SecretKind: Int] = [:]
        var byProject: [String: Int] = [:]
    }

    private let database: AppDatabase
    private let projectRepository: ProjectRepository
    private let tagRepository: TagRepository
    private var tasks: [Task<Void, Never>] = []

    init(database: AppDatabase, projects: ProjectRepository, tags: TagRepository) {
        self.database = database
        projectRepository = projects
        tagRepository = tags
    }

    func start() {
        guard tasks.isEmpty else { return }
        let dbQueue = database.dbQueue
        tasks = [
            observe(projectRepository.observation(), in: dbQueue) { [weak self] in self?.projects = $0 },
            observe(tagRepository.observation(), in: dbQueue) { [weak self] in self?.tags = $0 },
            observe(ValueObservation.tracking { db in try Self.counts(db) }, in: dbQueue) { [weak self] in self?.counts = $0 },
        ]
    }

    private func observe<Reducer: ValueReducer>(
        _ observation: ValueObservation<Reducer>, in dbQueue: DatabaseQueue,
        _ apply: @escaping @MainActor (Reducer.Value) -> Void
    ) -> Task<Void, Never> where Reducer.Value: Sendable {
        Task {
            do {
                for try await value in observation.values(in: dbQueue) { apply(value) }
            } catch {
                // Observation only fails if the database itself is gone; the
                // sidebar then simply stops updating.
            }
        }
    }

    nonisolated private static func counts(_ db: Database) throws -> Counts {
        var counts = Counts()
        let window = Date().addingTimeInterval(TimeInterval(SidebarSelection.expiringWindowDays) * 86_400)
        counts.trash = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items WHERE deleted_at IS NOT NULL") ?? 0
        for row in try Row.fetchAll(db, sql: "SELECT kind, project_id, favorite, expires_at FROM items WHERE deleted_at IS NULL") {
            counts.all += 1
            if row["favorite"] as Bool { counts.favorites += 1 }
            if let expires: Date = row["expires_at"], expires <= window { counts.expiring += 1 }
            if let kind = SecretKind(rawValue: row["kind"]) { counts.byKind[kind, default: 0] += 1 }
            if let projectId: String = row["project_id"] { counts.byProject[projectId, default: 0] += 1 }
        }
        return counts
    }

    // MARK: Project / tag edits (context menus)

    func renameProject(_ project: Project, to name: String) {
        var project = project
        project.name = name
        do { try projectRepository.update(project) } catch { lastError = Self.describeRename(error, name) }
    }

    func clearError() { lastError = nil }

    private static func describeRename(_ error: any Error, _ name: String) -> String {
        if let dbError = error as? DatabaseError, dbError.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            return String(localized: "“\(name)” is already in use.", bundle: AppLocale.bundle)
        }
        return error.localizedDescription
    }

    func setProjectColor(_ project: Project, _ color: String?) {
        var project = project
        project.color = color
        try? projectRepository.update(project)
    }

    func deleteProject(_ project: Project) {
        try? projectRepository.delete(id: project.id)
    }

    func renameTag(_ tag: Tag, to name: String) {
        do { try tagRepository.rename(id: tag.id, to: name) } catch { lastError = Self.describeRename(error, name) }
    }

    func deleteTag(_ tag: Tag) {
        try? tagRepository.delete(id: tag.id)
    }

    /// Drop target for item drags: moves the items into the project.
    func move(itemIds: [String], toProject projectId: String) {
        try? database.dbQueue.write { db in
            for id in itemIds {
                try db.execute(sql: "UPDATE items SET project_id = ?, updated_at = ? WHERE id = ?", arguments: [projectId, Date(), id])
            }
        }
    }
}
