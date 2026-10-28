import KeyCellarCore
import SwiftUI

/// Settings sections, listed in the middle column when the Settings sidebar
/// row is selected (System Settings style); the detail column shows the
/// chosen section's form.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, security, backup, appearance

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .security: "Security"
        case .backup: "Backup"
        case .appearance: "Appearance"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .security: "lock.shield"
        case .backup: "externaldrive"
        case .appearance: "paintpalette"
        }
    }
}

struct SettingsSectionList: View {
    @Binding var selection: SettingsSection

    var body: some View {
        List(SettingsSection.allCases, selection: Binding(get: { selection }, set: { if let s = $0 { selection = s } })) { section in
            Label(section.title, systemImage: section.systemImage).tag(section)
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
    }
}

/// One `Form` per section, `.formStyle(.grouped)` like SignalBar's and
/// MediaCatch's Settings pages.
struct SettingsView: View {
    let section: SettingsSection
    @Bindable var preferences: AppPreferences
    let backup: BackupManager
    private let notifier = AppServices.shared.expiryNotifier
    @AppStorage("themePreference") private var themePreferenceRaw = ThemePreference.system.rawValue
    @AppStorage("languagePreference") private var languageRaw = AppLocale.systemDefault.rawValue
    @State private var loginItemEnabled = LoginItemManager.shared.isEnabled
    @State private var loginItemNeedsApproval = LoginItemManager.shared.requiresApproval
    @State private var loginItemError: String?

    var body: some View {
        // Backup is its own Form: it presents sheets, and a `.sheet` hung on
        // a Section inside a Form never shows.
        if section == .backup {
            BackupSettingsView(backup: backup)
        } else {
            Form {
                switch section {
                case .general: general
                case .security: security
                case .appearance: appearance
                case .backup: EmptyView()
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private var general: some View {
        Section("Startup") {
            Toggle("Launch at login", isOn: Binding(get: { loginItemEnabled }, set: { setLoginItem($0) }))
            if loginItemNeedsApproval {
                Text("Approve KeyCellar under System Settings › General › Login Items to finish enabling this.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let loginItemError {
                Text(loginItemError).font(.callout).foregroundStyle(.red)
            }
        }
        Section("Quick Search") {
            HotKeyRecorderView(manager: AppServices.shared.hotKeys)
            Text("Works from any app. Enter copies the first match, ⌘Enter opens it.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var security: some View {
        Section("Auto-Lock") {
            Picker("Lock after inactivity", selection: $preferences.autoLock.idleTimeout) {
                Text("1 minute").tag(AutoLockPolicy.IdleTimeout.oneMinute)
                Text("5 minutes").tag(AutoLockPolicy.IdleTimeout.fiveMinutes)
                Text("15 minutes").tag(AutoLockPolicy.IdleTimeout.fifteenMinutes)
                Text("30 minutes").tag(AutoLockPolicy.IdleTimeout.thirtyMinutes)
                Text("Never").tag(AutoLockPolicy.IdleTimeout.never)
            }
            Toggle("Lock when the Mac sleeps", isOn: $preferences.autoLock.lockOnSleep)
            Toggle("Lock when the screen locks", isOn: $preferences.autoLock.lockOnScreenLock)
            Toggle("Lock when the app is hidden", isOn: $preferences.autoLock.lockWhenHidden)
        }
        Section("Default Expiry") {
            ForEach(SecretKind.allCases, id: \.self) { kind in
                Picker(kind.title, selection: Binding(
                    get: { preferences.expiry.ttl(for: kind) },
                    set: { preferences.expiry.ttlDays[kind] = $0 }
                )) {
                    ForEach(ExpiryPolicy.choices, id: \.self) { days in
                        Text(days == 0 ? "Never" : "\(days) days").tag(days)
                    }
                }
            }
            Text("Applied when an item is created or rotated. Reminders arrive 14, 7 and 1 day before, and on the day.")
                .font(.callout).foregroundStyle(.secondary)
            if notifier.authorizationStatus == .denied {
                HStack {
                    Label("Notifications are turned off for KeyCellar, so reminders can't be shown.", systemImage: "bell.slash")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open System Settings") { ExpiryNotifier.openSystemNotificationSettings() }
                }
            }
        }
        .task { await notifier.refreshAuthorizationStatus() }
        Section("Secrets") {
            Picker("Clear clipboard after", selection: $preferences.clipboardSeconds) {
                ForEach(AppPreferences.clipboardChoices, id: \.self) { Text("\($0) seconds").tag($0) }
            }
            Picker("Hide revealed values after", selection: $preferences.revealSeconds) {
                ForEach(AppPreferences.revealChoices, id: \.self) { Text("\($0) seconds").tag($0) }
            }
            Picker("One Touch ID covers reveals for", selection: $preferences.authReuseSeconds) {
                Text("Every reveal asks").tag(0)
                ForEach(AppPreferences.authReuseChoices.filter { $0 > 0 }, id: \.self) { Text("\($0) seconds").tag($0) }
            }
            Text("Every reveal and copy goes through the Secure Enclave, which asks for Touch ID or your login password itself. This setting only decides how long one answer is reused.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appearance: some View {
        Section("Appearance") {
            Picker("Theme", selection: $themePreferenceRaw) {
                ForEach(ThemePreference.allCases) { theme in
                    Text(theme.label).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Picker("Language", selection: Binding(
                get: { AppLocale(rawValue: languageRaw) ?? .systemDefault },
                set: { languageRaw = $0.rawValue }
            )) {
                Text("VI").tag(AppLocale.vi)
                Text("EN").tag(AppLocale.en)
            }
            .pickerStyle(.segmented)
        }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled {
                loginItemNeedsApproval = try LoginItemManager.shared.enable()
            } else {
                try LoginItemManager.shared.disable()
                loginItemNeedsApproval = false
            }
            loginItemEnabled = LoginItemManager.shared.isEnabled
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            loginItemEnabled = LoginItemManager.shared.isEnabled
        }
    }
}
