import AppKit
import SwiftUI

/// Brings the main window forward and restores the Dock icon — the one
/// sequence shared by Dock-icon reopen (`AppDelegate`), the menu bar panel
/// and Cmd+, (ported from SignalBar).
@MainActor
enum WindowPresenter {
    static let mainWindowID = "main"
    /// SwiftUI's own way to open the main window, kept by the status item
    /// (`OpenWindowKeeper`), for when there is no main window to bring forward.
    static var openWindow: OpenWindowAction?

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        // A window SwiftUI never made at launch, or one that was closed for
        // good, is opened anew: bringing forward only the windows there are
        // left the app with a Dock icon and nothing to show.
        if mainWindows(in: NSApp.windows).isEmpty {
            openWindow?(id: mainWindowID)
        }
        for window in mainWindows(in: NSApp.windows) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Only the main window, recognised by the delegate `WindowAccessor`
    /// gives it. `NSApp.windows` also lists the quick-search panel, the menu
    /// bar panel, the About window and hidden helper windows (text-field
    /// completion lists); ordering those front left an empty grey window
    /// floating over the detail column.
    static func mainWindows(in windows: [NSWindow]) -> [NSWindow] {
        windows.filter { $0.delegate is HideInsteadOfCloseDelegate }
    }

    /// Single entry point for both the app menu's "Settings…" (Cmd+,) and the
    /// menu bar panel's Settings button, so both land in the same in-window
    /// tab instead of a separate `Settings {}` window.
    static func showSettings() {
        showMainWindow()
        AppNavigationState.shared.sidebarSelection = .section(.settings)
    }
}

/// Keeps SwiftUI's `openWindow` for `WindowPresenter`. It sits, with no size,
/// in the status item, which is there from launch whether or not the main
/// window ever is.
struct OpenWindowKeeper: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { WindowPresenter.openWindow = openWindow }
    }
}
