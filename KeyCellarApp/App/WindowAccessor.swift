import AppKit
import SwiftUI

/// Intercepts the red close button to hide the window instead of destroying
/// it, and switches the Dock icon to Accessory, so the menu bar extra and
/// the global hotkey keep working after the window is "closed". Ported from
/// SignalBar.
final class HideInsteadOfCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // `sender.orderOut(nil)` alone leaves the NSWindow object alive but
        // invisible - macOS still counts it as an open window, so switching
        // to .accessory right after leaves Stage Manager showing a ghost
        // tile for a window with no visible content. `NSApp.hide(nil)` is
        // the same mechanism as Cmd+H: the whole app (and its windows) is
        // excluded from Stage Manager/Mission Control/Cmd+Tab while hidden,
        // which is what "hide instead of close" actually needs here.
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}

/// SwiftUI's `WindowGroup` has no direct API to intercept close behavior,
/// hide the title text, or mark a window capture-proof — this reaches into
/// AppKit once via `NSViewRepresentable` to grab the window and configure
/// all three. The title-bar treatment (`titleVisibility = .hidden` paired
/// with `titlebarAppearsTransparent` + `.fullSizeContentView`) is the same
/// as SignalBar / MediaCatch.
struct WindowAccessor: NSViewRepresentable {
    let delegate: HideInsteadOfCloseDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.delegate = delegate
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // Threat model T4: the window renders black in screenshots, screen
            // recordings and screen sharing. Every window and panel of this
            // app must set this — a revealed secret is exactly what a
            // screen-share accident captures.
            // DKB_ALLOW_CAPTURE lets a Debug build be screenshotted while
            // developing the UI; it does not exist in Release.
            #if DEBUG
            if ProcessInfo.processInfo.environment["DKB_ALLOW_CAPTURE"] == nil { window.sharingType = .none }
            #else
            window.sharingType = .none
            #endif
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
