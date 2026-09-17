import SwiftUI
import DKBSecretCore

@main
struct DKBSecretApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("themePreference") private var themePreferenceRaw = ThemePreference.system.rawValue
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue
    private let windowDelegate = HideInsteadOfCloseDelegate()

    private var themePreference: ThemePreference {
        ThemePreference(rawValue: themePreferenceRaw) ?? .system
    }

    private var appLocale: AppLocale {
        AppLocale(rawValue: languageRaw) ?? .systemDefault
    }

    // `.preferredColorScheme(nil)` is meant to hand control back to the OS,
    // but on an already-visible NSWindow that previously had an explicit
    // scheme applied, SwiftUI doesn't reliably clear the appearance it set
    // under the hood - switching Dark/Light -> System silently no-ops.
    // Driving `NSApp.appearance` directly (nil = follow the system) doesn't
    // have that staleness problem. (Same fix as DKB Monitor.)
    private func applyAppearance() {
        switch themePreference {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowAccessor(delegate: windowDelegate))
                .preferredColorScheme(themePreference.colorScheme)
                .environment(\.locale, appLocale.locale)
                .onAppear { applyAppearance() }
                .onChange(of: themePreferenceRaw) { _, _ in applyAppearance() }
        }
        .commands {
            // Settings is a sidebar tab in the main window (like DKB Monitor),
            // so Cmd+, routes there instead of opening a separate window.
            CommandGroup(replacing: .appSettings) {
                // Deferred one run-loop tick: mutating the sidebar selection
                // from inside the menu action left the sidebar List's
                // selection stuck in DKB Monitor (AppKit menu tracking mode).
                Button("Settings…") {
                    DispatchQueue.main.async { WindowPresenter.showSettings() }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Placeholder until Phase 7 (quick search, Lock now). `.window` style
        // because that phase needs a real view here, not plain menu items.
        MenuBarExtra {
            MenuBarContentView()
                .environment(\.locale, appLocale.locale)
        } label: {
            Image(systemName: "key.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
