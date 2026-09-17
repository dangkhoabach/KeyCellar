import Foundation
import GRDB

/// What the list column asks for: a scope (sidebar row), free-text search
/// over metadata, and a sort. Search never touches secret values — they are
/// ciphertext in the database, and that is the point.
public struct ItemQuery: Equatable, Sendable {
    public enum Scope: Equatable, Sendable {
        case all, favorites, recent, trash
        case expiring(withinDays: Int)
        case kind(SecretKind)
        case project(String)
        case tag(String)
    }

    public enum Sort: Equatable, Sendable {
        case title, lastUsed, created, expires
    }

    public var scope: Scope
    public var search: String
    public var sort: Sort

    public init(scope: Scope = .all, search: String = "", sort: Sort = .title) {
        self.scope = scope
        self.search = search
        self.sort = sort
    }
}

public struct ItemRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: Reads

    public func fetch(id: String) throws -> SecretItem? {
        try dbQueue.read { db in try SecretItem.fetchOne(db, key: id) }
    }

    public func fetch(_ query: ItemQuery, now: Date = Date()) throws -> [SecretItem] {
        try dbQueue.read { db in try Self.fetch(query, now: now, db) }
    }

    /// For `ValueObservation` in the app: re-runs the same query whenever
    /// any table it reads changes.
    public func observation(_ query: ItemQuery) -> ValueObservation<ValueReducers.Fetch<[SecretItem]>> {
        ValueObservation.tracking { db in try Self.fetch(query, now: Date(), db) }
    }

    static func fetch(_ query: ItemQuery, now: Date, _ db: Database) throws -> [SecretItem] {
        var sql = "SELECT i.* FROM items i"
        var conditions: [String] = []
        var arguments: [DatabaseValueConvertible] = []

        switch query.scope {
        case .trash:
            conditions.append("i.deleted_at IS NOT NULL")
        default:
            conditions.append("i.deleted_at IS NULL")
        }

        switch query.scope {
        case .all, .trash:
            break
        case .favorites:
            conditions.append("i.favorite = 1")
        case .recent:
            conditions.append("i.last_used_at IS NOT NULL")
        case .expiring(let days):
            conditions.append("i.expires_at IS NOT NULL AND i.expires_at <= ?")
            arguments.append(now.addingTimeInterval(TimeInterval(days) * 86_400))
        case .kind(let kind):
            conditions.append("i.kind = ?")
            arguments.append(kind.rawValue)
        case .project(let projectId):
            conditions.append("i.project_id = ?")
            arguments.append(projectId)
        case .tag(let tagId):
            conditions.append("EXISTS (SELECT 1 FROM item_tags it WHERE it.item_id = i.id AND it.tag_id = ?)")
            arguments.append(tagId)
        }

        let search = query.search.trimmingCharacters(in: .whitespaces)
        if !search.isEmpty {
            let pattern = "%\(search)%"
            conditions.append("""
                (i.title LIKE ? OR i.service LIKE ? OR i.username LIKE ? OR i.url LIKE ?
                 OR EXISTS (SELECT 1 FROM projects p WHERE p.id = i.project_id AND p.name LIKE ?)
                 OR EXISTS (SELECT 1 FROM item_tags it JOIN tags t ON t.id = it.tag_id
                            WHERE it.item_id = i.id AND t.name LIKE ?))
                """)
            arguments.append(contentsOf: Array(repeating: pattern, count: 6))
        }

        sql += " WHERE " + conditions.joined(separator: " AND ")

        // `recent` is defined by its ordering, whatever sort the list asked for.
        switch (query.scope, query.sort) {
        case (.recent, _), (_, .lastUsed):
            sql += " ORDER BY i.last_used_at DESC, i.title COLLATE NOCASE"
        case (_, .title):
            sql += " ORDER BY i.title COLLATE NOCASE"
        case (_, .created):
            sql += " ORDER BY i.created_at DESC"
        case (_, .expires):
            sql += " ORDER BY i.expires_at IS NULL, i.expires_at, i.title COLLATE NOCASE"
        }

        return try SecretItem.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }

    public func tags(for itemId: String) throws -> [Tag] {
        try dbQueue.read { db in
            try Tag.fetchAll(db, sql: """
                SELECT t.* FROM tags t JOIN item_tags it ON it.tag_id = t.id
                WHERE it.item_id = ? ORDER BY t.name COLLATE NOCASE
                """, arguments: [itemId])
        }
    }

    public func blobs(for itemId: String) throws -> [SecretBlob] {
        try dbQueue.read { db in
            try SecretBlob
                .filter(Column("item_id") == itemId)
                .order(Column("field"), Column("slot"))
                .fetchAll(db)
        }
    }

    // MARK: Writes (called inside `SecretVault`'s transactions)

    static func setTags(_ names: [String], for itemId: String, _ db: Database) throws {
        try db.execute(sql: "DELETE FROM item_tags WHERE item_id = ?", arguments: [itemId])
        for name in Set(names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) {
            let tag = try Tag.filter(Column("name") == name).fetchOne(db) ?? {
                let tag = Tag(name: name)
                try tag.insert(db)
                return tag
            }()
            try db.execute(sql: "INSERT INTO item_tags (item_id, tag_id) VALUES (?, ?)", arguments: [itemId, tag.id])
        }
    }

    public func setFavorite(_ favorite: Bool, itemId: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE items SET favorite = ? WHERE id = ?", arguments: [favorite, itemId])
        }
    }
}
