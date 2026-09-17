import SwiftUI

/// Static sidebar rows. Kinds, projects and tags are data-driven and join the
/// sidebar in Phase 4; Settings is a tab here (not a `Settings {}` scene) so
/// Cmd+, and the menu bar extra land in one place, as in DKB Monitor.
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
