import Foundation

/// When the vault locks on its own. Pure decision logic;
/// the app's `IdleMonitor` feeds it events. Defaults are the safe side of
/// every switch.
public struct AutoLockPolicy: Equatable, Sendable {
    public enum IdleTimeout: Int, CaseIterable, Sendable {
        case oneMinute = 60
        case fiveMinutes = 300
        case fifteenMinutes = 900
        case thirtyMinutes = 1800
        case never = 0
    }

    public enum Event: Equatable, Sendable {
        case idle(seconds: TimeInterval)
        case willSleep
        case screenLocked
        case appHidden
    }

    public var idleTimeout: IdleTimeout
    public var lockOnSleep: Bool
    public var lockOnScreenLock: Bool
    public var lockWhenHidden: Bool

    public init(
        idleTimeout: IdleTimeout = .fiveMinutes,
        lockOnSleep: Bool = true,
        lockOnScreenLock: Bool = true,
        lockWhenHidden: Bool = false
    ) {
        self.idleTimeout = idleTimeout
        self.lockOnSleep = lockOnSleep
        self.lockOnScreenLock = lockOnScreenLock
        self.lockWhenHidden = lockWhenHidden
    }

    public func shouldLock(on event: Event) -> Bool {
        switch event {
        case .idle(let seconds):
            idleTimeout != .never && seconds >= TimeInterval(idleTimeout.rawValue)
        case .willSleep:
            lockOnSleep
        case .screenLocked:
            lockOnScreenLock
        case .appHidden:
            lockWhenHidden
        }
    }

    // MARK: Persistence in the `settings` table

    static let idleKey = "autoLock.idleSeconds"
    static let sleepKey = "autoLock.onSleep"
    static let screenLockKey = "autoLock.onScreenLock"
    static let hiddenKey = "autoLock.whenHidden"

    public static func load(from settings: SettingsRepository) throws -> AutoLockPolicy {
        var policy = AutoLockPolicy()
        if let raw = try settings.get(idleKey).flatMap(Int.init), let timeout = IdleTimeout(rawValue: raw) {
            policy.idleTimeout = timeout
        }
        if let raw = try settings.get(sleepKey) { policy.lockOnSleep = raw == "1" }
        if let raw = try settings.get(screenLockKey) { policy.lockOnScreenLock = raw == "1" }
        if let raw = try settings.get(hiddenKey) { policy.lockWhenHidden = raw == "1" }
        return policy
    }

    public func save(to settings: SettingsRepository) throws {
        try settings.set(Self.idleKey, String(idleTimeout.rawValue))
        try settings.set(Self.sleepKey, lockOnSleep ? "1" : "0")
        try settings.set(Self.screenLockKey, lockOnScreenLock ? "1" : "0")
        try settings.set(Self.hiddenKey, lockWhenHidden ? "1" : "0")
    }
}
