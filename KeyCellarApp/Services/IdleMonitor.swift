import AppKit
import KeyCellarCore

/// Turns system events into `AutoLockPolicy.Event`s and calls `onLock` when
/// the policy says so. Idle time is polled (there is no push API for "the
/// user stopped typing"); sleep, screen lock and app hide are notifications.
/// All of these were confirmed to work inside the sandbox.
@MainActor
final class IdleMonitor {
    private let policy: () -> AutoLockPolicy
    private let onLock: () -> Void
    private var poll: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    static let pollInterval: Duration = .seconds(15)

    init(policy: @escaping () -> AutoLockPolicy, onLock: @escaping () -> Void) {
        self.policy = policy
        self.onLock = onLock
    }

    func start() {
        stop()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                handle(.idle(seconds: Self.secondsSinceLastInput()))
            }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.handle(.willSleep) } },
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.handle(.screenLocked) } },
            NotificationCenter.default.addObserver(
                forName: NSApplication.didHideNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.handle(.appHidden) } },
        ]
    }

    func stop() {
        poll?.cancel()
        poll = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
    }

    func handle(_ event: AutoLockPolicy.Event) {
        if policy().shouldLock(on: event) { onLock() }
    }

    /// Seconds since any keyboard/mouse/trackpad event in this login
    /// session. No Accessibility permission needed.
    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
