import AppKit

/// Minimal AppKit glue for the behaviors SwiftUI Scenes don't expose: keep
/// running after the last window closes, reopen on Dock click, and restore
/// the Regular activation policy (Dock icon) when reopening. Same shape as
/// DKB Monitor's `AppDelegate`, minus everything that app starts at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--seed-sample-data") {
            Task { await SampleData.seed(services: .shared) }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        WindowPresenter.showMainWindow()
        // Reopen is already fully handled above - returning true would also
        // let AppKit run its default reopen handling, which for a SwiftUI
        // WindowGroup means instantiating a brand-new window since
        // hasVisibleWindows is false (the window was hidden, not closed).
        return false
    }
}
