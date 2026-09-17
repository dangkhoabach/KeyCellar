import Foundation

/// The five item types of v1 (plan §5.2). Each is its own kind because its
/// field template or behaviour differs — a token is just an `apiKey` with a
/// different name, so it isn't one.
public enum SecretKind: String, Codable, CaseIterable, Sendable {
    case apiKey, login, sshKey, envSet, secureNote

    public var template: KindTemplate { KindTemplate.templates[self]! }
}

/// One field of an item. `isSecret` decides where the value lives: metadata
/// goes into the `items` row as searchable plaintext, secrets go into
/// `secret_blobs` as HPKE ciphertext (plan §3.2 D4).
public struct FieldSpec: Equatable, Sendable {
    public let key: String
    public let label: String
    public let isSecret: Bool
    /// The value Cmd+C copies without asking which field.
    public let isPrimary: Bool
    public let isMultiline: Bool

    init(_ key: String, _ label: String, secret: Bool = false, primary: Bool = false, multiline: Bool = false) {
        self.key = key
        self.label = label
        isSecret = secret
        isPrimary = primary
        isMultiline = multiline
    }
}

/// Field templates are data, not view code, so adding a kind later is one
/// entry here. `title` is not listed: every kind has it and it maps to the
/// `items.title` column directly, as do `service`, `environment`, `url` and
/// `username` when a template uses those keys; any other metadata key lands
/// in `items.metadata_json`.
public struct KindTemplate: Sendable {
    public let kind: SecretKind
    public let fields: [FieldSpec]

    public var secretFields: [FieldSpec] { fields.filter(\.isSecret) }
    public var primaryField: FieldSpec? { fields.first(where: \.isPrimary) }

    static let templates: [SecretKind: KindTemplate] = [
        .apiKey: KindTemplate(kind: .apiKey, fields: [
            FieldSpec("service", "Service"),
            FieldSpec("url", "URL"),
            FieldSpec("environment", "Environment"),
            FieldSpec("username", "Account ID"),
            FieldSpec("key", "Key", secret: true, primary: true),
            FieldSpec("notes", "Notes", secret: true, multiline: true),
        ]),
        .login: KindTemplate(kind: .login, fields: [
            FieldSpec("url", "URL"),
            FieldSpec("username", "Username"),
            FieldSpec("password", "Password", secret: true, primary: true),
            FieldSpec("notes", "Notes", secret: true, multiline: true),
        ]),
        .sshKey: KindTemplate(kind: .sshKey, fields: [
            FieldSpec("host", "Host"),
            FieldSpec("username", "Username"),
            FieldSpec("publicKey", "Public Key", multiline: true),
            FieldSpec("privateKey", "Private Key", secret: true, primary: true, multiline: true),
            FieldSpec("passphrase", "Passphrase", secret: true),
            FieldSpec("notes", "Notes", secret: true, multiline: true),
        ]),
        // The KEY=VALUE pairs are dynamic: each VALUE is its own blob under
        // the field name "env.<KEY>" (see `SecretItem.envFieldPrefix`).
        .envSet: KindTemplate(kind: .envSet, fields: [
            FieldSpec("environment", "Environment"),
            FieldSpec("notes", "Notes", secret: true, multiline: true),
        ]),
        .secureNote: KindTemplate(kind: .secureNote, fields: [
            FieldSpec("body", "Note", secret: true, primary: true, multiline: true),
        ]),
    ]
}

public enum DeploymentEnvironment: String, Codable, CaseIterable, Sendable {
    case dev, staging, prod
}
