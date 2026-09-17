import Foundation

/// Default lifetime per kind (plan §8 Phase 8), applied when an item is
/// created or rotated. Stored per kind in `settings`; 0 = no expiry.
public struct ExpiryPolicy: Equatable, Sendable {
    public static let choices = [0, 30, 90, 180, 365]

    public var ttlDays: [SecretKind: Int]

    public init(ttlDays: [SecretKind: Int] = Self.defaults) {
        self.ttlDays = ttlDays
    }

    public static let defaults: [SecretKind: Int] = [
        .apiKey: 90, .login: 180, .sshKey: 365, .envSet: 0, .secureNote: 0,
    ]

    public func ttl(for kind: SecretKind) -> Int {
        ttlDays[kind] ?? Self.defaults[kind] ?? 0
    }

    public func expiryDate(for kind: SecretKind, from now: Date = Date()) -> Date? {
        let days = ttl(for: kind)
        return days > 0 ? Calendar.current.date(byAdding: .day, value: days, to: now) : nil
    }

    static func key(_ kind: SecretKind) -> String { "expiry.ttlDays.\(kind.rawValue)" }

    public static func load(from settings: SettingsRepository) throws -> ExpiryPolicy {
        var policy = ExpiryPolicy()
        for kind in SecretKind.allCases {
            if let raw = try settings.get(key(kind)), let days = Int(raw), choices.contains(days) {
                policy.ttlDays[kind] = days
            }
        }
        return policy
    }

    public func save(to settings: SettingsRepository) throws {
        for kind in SecretKind.allCases {
            try settings.set(Self.key(kind), String(ttl(for: kind)))
        }
    }
}

/// Which expiry reminders are due. Milestones are days-before-expiry; an
/// item is reminded once per milestone per expiry date, and only for the
/// most urgent milestone it has crossed, so a key found three days before
/// expiry gets one "3 days left" reminder rather than the 14- and 7-day
/// ones on top.
public enum ExpiryMilestones {
    public static let milestones = [14, 7, 1, 0]

    public struct Reminder: Equatable, Sendable {
        public let item: SecretItem
        public let milestone: Int
        public let daysLeft: Int

        /// Marker key: once notified, stored so the same reminder never
        /// fires again. A rotation gives the item a new expiry date and
        /// therefore fresh keys.
        public var markerKey: String { Self.markerKey(itemId: item.id, expiresAt: item.expiresAt!, milestone: milestone) }

        public static func markerKey(itemId: String, expiresAt: Date, milestone: Int) -> String {
            "notified.\(itemId).\(Int(expiresAt.timeIntervalSince1970)).\(milestone)"
        }
    }

    public static func due(_ items: [SecretItem], now: Date = Date(), alreadyNotified: (String) -> Bool) -> [Reminder] {
        items.compactMap { item in
            guard item.deletedAt == nil, let expires = item.expiresAt else { return nil }
            let daysLeft = Int(ceil(expires.timeIntervalSince(now) / 86_400))
            // The most urgent milestone crossed; nothing once it's past due
            // by more than a day (the sidebar badge covers that).
            guard daysLeft >= -1, let milestone = milestones.last(where: { daysLeft <= $0 }) ?? nil else { return nil }
            let reminder = Reminder(item: item, milestone: milestone, daysLeft: max(daysLeft, 0))
            return alreadyNotified(reminder.markerKey) ? nil : reminder
        }
    }

    /// All marker keys at or above `milestone` — marking them together is
    /// what keeps the less urgent reminders from firing later.
    public static func markerKeysToSet(for reminder: Reminder) -> [String] {
        milestones.filter { $0 >= reminder.milestone }.map {
            Reminder.markerKey(itemId: reminder.item.id, expiresAt: reminder.item.expiresAt!, milestone: $0)
        }
    }
}
