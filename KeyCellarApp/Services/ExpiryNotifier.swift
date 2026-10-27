import AppKit
import KeyCellarCore
import UserNotifications

/// Posts "expires in N days" reminders: checks on launch,
/// every hour and after wake; each (item, expiry date, milestone) fires
/// once, tracked through marker keys in `settings`. Clicking a reminder
/// opens the item. Same `UNUserNotificationCenter` pattern as SignalBar.
@MainActor
@Observable
final class ExpiryNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// For Settings: warn when macOS won't show the reminders.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let items: ItemRepository
    private let settings: SettingsRepository
    private let onOpen: (String) -> Void
    private var loop: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    static let checkInterval: Duration = .seconds(3600)

    init(items: ItemRepository, settings: SettingsRepository, onOpen: @escaping (String) -> Void) {
        self.items = items
        self.settings = settings
        self.onOpen = onOpen
        super.init()
    }

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func openSystemNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    func check(now: Date = Date()) async {
        await refreshAuthorizationStatus()
        guard let all = try? items.fetch(ItemQuery(scope: .all, sort: .expires), now: now) else { return }
        let settings = self.settings
        let due = ExpiryMilestones.due(all, now: now) { key in (try? settings.get(key)) != nil }
        guard !due.isEmpty else { return }
        // `add` succeeds even when notifications are denied, and the user
        // would never see the reminder — so only record a reminder as sent
        // once macOS will actually show it. Until then it stays due.
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        authorizationStatus = status
        guard status == .authorized || status == .provisional else { return }
        for reminder in due {
            let content = UNMutableNotificationContent()
            content.title = reminder.item.title
            let bundle = AppLocale.bundle
            content.body = switch reminder.daysLeft {
            case 0: String(localized: "Expires today. Rotate it in KeyCellar.", bundle: bundle)
            case 1: String(localized: "Expires tomorrow.", bundle: bundle)
            default: String(localized: "Expires in \(reminder.daysLeft) days.", bundle: bundle)
            }
            content.sound = .default
            content.userInfo = ["itemId": reminder.item.id]
            let request = UNNotificationRequest(identifier: reminder.markerKey, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
                for key in ExpiryMilestones.markerKeysToSet(for: reminder) {
                    try? settings.set(key, "1")
                }
            } catch {
                // Not recorded: it stays due for the next check.
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let itemId = response.notification.request.content.userInfo["itemId"] as? String else { return }
        await MainActor.run { onOpen(itemId) }
    }
}
