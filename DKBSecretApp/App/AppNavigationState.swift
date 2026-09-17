import Observation

/// Sidebar selection, shared between `ContentView` and whatever triggers
/// navigation from outside the view hierarchy (`WindowPresenter.showSettings`,
/// later the menu bar extra and notification click-through).
@MainActor
@Observable
final class AppNavigationState {
    static let shared = AppNavigationState()

    var sidebarSelection: SidebarSection = .all

    private init() {}
}
