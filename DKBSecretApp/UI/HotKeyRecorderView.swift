import AppKit
import SwiftUI

/// Settings › General row: shows the shortcut, and while recording takes
/// the next key press (with ⌘/⌥/⌃) as the new one.
struct HotKeyRecorderView: View {
    let manager: HotKeyManager
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent("Quick search shortcut") {
            HStack {
                Button(recording ? "Press keys…" : manager.hotKey.displayString) {
                    recording ? stop() : start()
                }
                .frame(minWidth: 110)
                if recording {
                    Button("Cancel") { stop() }
                }
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in stop() }
                return nil
            }
            if let hotKey = HotKey(event: event) {
                Task { @MainActor in
                    manager.update(hotKey)
                    stop()
                }
                return nil
            }
            return event
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
