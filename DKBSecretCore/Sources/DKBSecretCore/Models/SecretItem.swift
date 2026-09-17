import Foundation
import GRDB

/// The metadata half of a vault entry — everything that is searchable and
/// safe to keep as plaintext. Secret values live in `SecretBlob` rows.
public struct SecretItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: SecretKind
    public var title: String
    public var projectId: String?
    public var service: String?
    public var environment: DeploymentEnvironment?
    public var url: String?
    public var username: String?
    /// Template metadata keys that have no column of their own (host,
    /// publicKey…), stored as one JSON object.
    public var metadata: [String: String]
    public var favorite: Bool
    public var expiresAt: Date?
    public var lastUsedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    /// Set = in the Trash. Rows are purged for real 30 days later.
    public var deletedAt: Date?

    public init(
        id: String = UUID().uuidString,
        kind: SecretKind,
        title: String,
        projectId: String? = nil,
        service: String? = nil,
        environment: DeploymentEnvironment? = nil,
        url: String? = nil,
        username: String? = nil,
        metadata: [String: String] = [:],
        favorite: Bool = false,
        expiresAt: Date? = nil,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.projectId = projectId
        self.service = service
        self.environment = environment
        self.url = url
        self.username = username
        self.metadata = metadata
        self.favorite = favorite
        self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Field-name prefix for the dynamic KEY=VALUE blobs of an `envSet`.
    public static let envFieldPrefix = "env."
}

extension SecretItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "items"

    enum CodingKeys: String, CodingKey {
        case id, kind, title
        case projectId = "project_id"
        case service, environment, url, username
        case metadata = "metadata_json"
        case favorite
        case expiresAt = "expires_at"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    // `metadata` is a dictionary; GRDB's Codable support stores nested
    // Codable values as JSON text automatically, which is exactly the
    // `metadata_json` column.
}

public struct Project: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sortOrder: Int
    public var color: String?

    public init(id: String = UUID().uuidString, name: String, sortOrder: Int = 0, color: String? = nil) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.color = color
    }
}

extension Project: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "projects"

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case sortOrder = "sort_order"
    }
}

public struct Tag: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

extension Tag: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "tags"
}

/// One HPKE-sealed value. `slot` 0 is the current value; 1…`historyLimit`
/// are previous values, 1 being the most recent (plan §5.3).
public struct SecretBlob: Codable, Identifiable, Equatable, Sendable {
    public static let historyLimit = 5

    public var id: String
    public var itemId: String
    public var field: String
    public var slot: Int
    public var encapsulatedKey: Data
    public var ciphertext: Data
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        itemId: String,
        field: String,
        slot: Int = 0,
        encapsulatedKey: Data,
        ciphertext: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.itemId = itemId
        self.field = field
        self.slot = slot
        self.encapsulatedKey = encapsulatedKey
        self.ciphertext = ciphertext
        self.createdAt = createdAt
    }
}

extension SecretBlob: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "secret_blobs"

    enum CodingKeys: String, CodingKey {
        case id, field, slot, ciphertext
        case itemId = "item_id"
        case encapsulatedKey = "encapsulated_key"
        case createdAt = "created_at"
    }
}
