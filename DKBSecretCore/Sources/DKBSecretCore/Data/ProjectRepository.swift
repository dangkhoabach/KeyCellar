import Foundation
import GRDB

public struct ProjectRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func all() throws -> [Project] {
        try dbQueue.read { db in
            try Project.order(Column("sort_order"), Column("name").collating(.nocase)).fetchAll(db)
        }
    }

    public func observation() -> ValueObservation<ValueReducers.Fetch<[Project]>> {
        ValueObservation.tracking { db in
            try Project.order(Column("sort_order"), Column("name").collating(.nocase)).fetchAll(db)
        }
    }

    /// Returns the existing project of that name rather than failing on the
    /// UNIQUE constraint — the form's "create inline" path needs exactly that.
    @discardableResult
    public func findOrCreate(name: String) throws -> Project {
        try dbQueue.write { db in
            if let existing = try Project.filter(Column("name") == name).fetchOne(db) { return existing }
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM projects") ?? 0
            let project = Project(name: name, sortOrder: next)
            try project.insert(db)
            return project
        }
    }

    public func update(_ project: Project) throws {
        try dbQueue.write { db in try project.update(db) }
    }

    /// Items keep existing with `project_id` reset to NULL (schema `ON DELETE SET NULL`).
    public func delete(id: String) throws {
        try dbQueue.write { db in _ = try Project.deleteOne(db, key: id) }
    }
}

public struct TagRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func all() throws -> [Tag] {
        try dbQueue.read { db in try Tag.order(Column("name").collating(.nocase)).fetchAll(db) }
    }

    public func observation() -> ValueObservation<ValueReducers.Fetch<[Tag]>> {
        ValueObservation.tracking { db in try Tag.order(Column("name").collating(.nocase)).fetchAll(db) }
    }

    public func rename(id: String, to name: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE tags SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    public func delete(id: String) throws {
        try dbQueue.write { db in _ = try Tag.deleteOne(db, key: id) }
    }
}
