import AppKit
import Testing
@testable import KeyCellar

@MainActor
@Suite struct WindowPresenterReopenTests {
    /// With no main window at all (SwiftUI made none at launch, or it was
    /// closed for good), Show KeyCellar and the Dock icon open a new one
    /// rather than bringing forward nothing.
    @Test func showMainWindowOpensOneWhenThereIsNone() async throws {
        // Closed for good: without its delegate the close isn't turned into a hide.
        let closed = WindowPresenter.mainWindows(in: NSApp.windows)
        let delegate = closed.first?.delegate
        for window in closed {
            window.delegate = nil
            window.close()
        }
        defer {
            // SwiftUI may bring back the same window; it gets its delegate again.
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(WindowPresenter.mainWindowID) == true && window.delegate == nil {
                window.delegate = delegate
            }
        }
        #expect(WindowPresenter.mainWindows(in: NSApp.windows).isEmpty)
        #expect(WindowPresenter.openWindow != nil)

        WindowPresenter.showMainWindow()
        func shown() -> Bool {
            NSApp.windows.contains { $0.isVisible && $0.identifier?.rawValue.hasPrefix(WindowPresenter.mainWindowID) == true }
        }
        for _ in 0..<40 where !shown() {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(shown())
    }
}
