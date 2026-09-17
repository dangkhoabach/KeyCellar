import DKBSecretCore
import SwiftUI

/// Static sidebar rows. Kinds, projects and tags are data-driven and join
/// them through `SidebarSelection`; Settings is a tab here (not a
/// `Settings {}` scene) so Cmd+, and the menu bar extra land in one place,
/// as in DKB Monitor.
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case all, favorites, recent, expiring, trash, settings

    var id: Self { self }

    /// `LocalizedStringKey` (not `String`) so Xcode's String Catalog
    /// extraction picks it up.
    var title: LocalizedStringKey {
        switch self {
        case .all: "All Items"
        case .favorites: "Favorites"
        case .recent: "Recently Used"
        case .expiring: "Expiring Soon"
        case .trash: "Trash"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .favorites: "star"
        case .recent: "clock"
        case .expiring: "exclamationmark.triangle"
        case .trash: "trash"
        case .settings: "gearshape"
        }
    }
}

/// What the sidebar's `List(selection:)` holds.
enum SidebarSelection: Hashable {
    case section(SidebarSection)
    case kind(SecretKind)
    case project(String)
    case tag(String)

    /// Days before expiry that count as "expiring soon" (plan §6).
    static let expiringWindowDays = 14

    var scope: ItemQuery.Scope {
        switch self {
        case .section(.all), .section(.settings): .all
        case .section(.favorites): .favorites
        case .section(.recent): .recent
        case .section(.expiring): .expiring(withinDays: Self.expiringWindowDays)
        case .section(.trash): .trash
        case .kind(let kind): .kind(kind)
        case .project(let id): .project(id)
        case .tag(let id): .tag(id)
        }
    }

    var isTrash: Bool { self == .section(.trash) }
    var isSettings: Bool { self == .section(.settings) }
}

extension SecretKind {
    var title: LocalizedStringKey {
        switch self {
        case .apiKey: "API Keys"
        case .login: "Logins"
        case .sshKey: "SSH Keys"
        case .envSet: ".env Sets"
        case .secureNote: "Secure Notes"
        }
    }

    var singularTitle: LocalizedStringKey {
        switch self {
        case .apiKey: "API Key"
        case .login: "Login"
        case .sshKey: "SSH Key"
        case .envSet: ".env Set"
        case .secureNote: "Secure Note"
        }
    }

    var systemImage: String {
        switch self {
        case .apiKey: "key.horizontal"
        case .login: "person.badge.key"
        case .sshKey: "terminal"
        case .envSet: "list.bullet.rectangle"
        case .secureNote: "note.text"
        }
    }
}

extension DeploymentEnvironment {
    var title: LocalizedStringKey {
        switch self {
        case .dev: "Development"
        case .staging: "Staging"
        case .prod: "Production"
        }
    }

    var color: Color {
        switch self {
        case .dev: .blue
        case .staging: .orange
        case .prod: .red
        }
    }
}
