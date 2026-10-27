import KeyCellarCore
import Observation

/// Sidebar and item selection, shared between the columns and whatever
/// drives navigation from outside the view hierarchy
/// (`WindowPresenter.showSettings`, the menu bar extra, notifications).
@MainActor
@Observable
final class AppNavigationState {
    static let shared = AppNavigationState()

    var sidebarSelection: SidebarSelection = .section(.all)
    var selectedItemIds: Set<String> = []

    /// The item the detail column shows: exactly one selected.
    var selectedItemId: String? {
        selectedItemIds.count == 1 ? selectedItemIds.first : nil
    }

    private init() {}

    func show(itemId: String) {
        selectedItemIds = [itemId]
    }
}
