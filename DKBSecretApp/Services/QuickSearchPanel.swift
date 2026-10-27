import AppKit
import DKBSecretCore
import SwiftUI

/// The floating quick-search window (⌥⌘S by default): a non-activating
/// panel, so it takes keystrokes without switching away from the app the
/// user is in, and closes as soon as it loses key status or on Escape.
/// Capture-proof like every other window of the app.
@MainActor
final class QuickSearchPanel: NSPanel, NSWindowDelegate {
    private let model: QuickSearchModel

    init(model: QuickSearchModel, onCopy: @escaping (SecretItem) -> Void, onOpen: @escaping (SecretItem) -> Void) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered, defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        #if DEBUG
        if ProcessInfo.processInfo.environment["DKB_ALLOW_CAPTURE"] == nil { sharingType = .none }
        #else
        sharingType = .none
        #endif
        isReleasedWhenClosed = false
        delegate = self
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let view = QuickSearchView(model: model, onCopy: { [weak self] item in
            self?.dismiss()
            onCopy(item)
        }, onOpen: { [weak self] item in
            self?.dismiss()
            onOpen(item)
        }, onDismiss: { [weak self] in
            self?.dismiss()
        })
        // preferredContentSize: the panel follows the SwiftUI content as the
        // result list grows and shrinks.
        let host = NSHostingController(rootView: view.frame(width: 560))
        host.sizingOptions = [.preferredContentSize]
        contentViewController = host
    }

    override var canBecomeKey: Bool { true }

    func toggle() {
        isVisible ? dismiss() : present()
    }

    func present() {
        model.reset()
        // Upper third of the screen the mouse is on, like Spotlight.
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let screen {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(x: frame.midX - 280, y: frame.maxY - frame.height * 0.28 - self.frame.height))
        }
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
        model.reset()
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}
