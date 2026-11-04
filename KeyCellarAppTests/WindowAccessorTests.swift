import AppKit
import Testing
@testable import KeyCellar

@MainActor
@Suite struct WindowAccessorTests {
    /// Opening the menu bar extra unhides the app, which puts back every
    /// window the hide took away; the closed main window must not be one.
    @Test func aClosedWindowStaysClosedWhenTheAppUnhides() {
        let delegate = HideInsteadOfCloseDelegate()
        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        main.delegate = delegate
        main.orderFront(nil)
        defer {
            main.orderOut(nil)
            NSApp.setActivationPolicy(.regular)
        }

        #expect(delegate.windowShouldClose(main) == false)
        NSApp.unhide(nil)

        #expect(!main.isVisible)
    }
}
