import AppKit

/// Minimal AppKit glue for the behaviors SwiftUI Scenes don't expose: keep
/// running after the last window closes, reopen on Dock click, and restore
/// the Regular activation policy (Dock icon) when reopening. Same shape as
/// SignalBar's `AppDelegate`, minus everything that app starts at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let services = AppServices.shared
        // A vault that cannot reach its database or its enclave key must not
        // pretend to be an empty one — say so and quit.
        if let failure = services.startupFailure {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = String(localized: "KeyCellar can't open the vault", bundle: AppLocale.bundle)
            alert.informativeText = failure
            alert.addButton(withTitle: String(localized: "Quit", bundle: AppLocale.bundle))
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        services.idleMonitor.start()
        services.hotKeys.start()
        services.expiryNotifier.start()
        Task { try? await services.vault.purgeTrash() }
        #if DEBUG
        if CommandLine.arguments.contains("--seed-sample-data") {
            Task { await SampleData.seed(services: services) }
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
