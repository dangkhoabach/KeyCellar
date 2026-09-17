import AppKit

/// Brings the main window forward and restores the Dock icon — the one
/// sequence shared by Dock-icon reopen (`AppDelegate`), the menu bar extra's
/// "Open" item and Cmd+, (ported from DKB Monitor).
@MainActor
enum WindowPresenter {
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Single entry point for both the app menu's "Settings…" (Cmd+,) and the
    /// menu bar extra's "Settings…" item, so both land in the same in-window
    /// tab instead of a separate `Settings {}` window.
    static func showSettings() {
        showMainWindow()
        AppNavigationState.shared.sidebarSelection = .section(.settings)
    }
}
