import SwiftUI
import DKBSecretCore

@main
struct DKBSecretApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("themePreference") private var themePreferenceRaw = ThemePreference.system.rawValue
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue
    private let windowDelegate = HideInsteadOfCloseDelegate()

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--reset-debug-vault") { AppDatabaseLocation.resetDebugVault() }
        #endif
    }

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
            CommandGroup(replacing: .newItem) {
                Button("New Item…") { AppServices.shared.actions.newItem() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Item from Clipboard…") { AppServices.shared.actions.newItemFromClipboard() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
            }
            // ⌘C on a selected item goes through the list's `onCopyCommand`
            // (so text fields keep their own copy); these are the secondary
            // copies from plan §7.2.
            CommandMenu("Item") {
                Button("Copy Username") { AppServices.shared.actions.copyUsernameOfSelection() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Copy URL") { AppServices.shared.actions.copyURLOfSelection() }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Divider()
                Button("Edit…") { AppServices.shared.actions.editSelection() }
                    .keyboardShortcut("e", modifiers: .command)
                Button("Delete Permanently") { AppServices.shared.actions.purgeSelection() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                Divider()
                Button("Lock Vault") { AppServices.shared.session.lock() }
                    .keyboardShortcut("l", modifiers: .command)
            }
            #if DEBUG
            CommandMenu("Debug") {
                Button("Seed Sample Data") { Task { await SampleData.seed(services: .shared) } }
            }
            #endif
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
