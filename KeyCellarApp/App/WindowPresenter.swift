import AppKit

/// Brings the main window forward and restores the Dock icon — the one
/// sequence shared by Dock-icon reopen (`AppDelegate`), the menu bar extra's
/// "Open" item and Cmd+, (ported from DKB Monitor).
@MainActor
enum WindowPresenter {
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        // Only real document-level windows: `NSApp.windows` also lists the
        // quick-search panel and hidden helper windows (text-field completion
        // lists, the menu bar extra's popover), and ordering those front left
        // an empty grey window floating over the detail column.
        for window in NSApp.windows where !(window is NSPanel) && window.level == .normal {
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
