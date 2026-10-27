import Foundation
import Testing
@testable import KeyCellarCore

@Suite struct ExpiryPolicyTests {
    @Test func defaultsPerKindAndZeroMeansNever() {
        let policy = ExpiryPolicy()
        #expect(policy.ttl(for: .apiKey) == 90)
        #expect(policy.ttl(for: .sshKey) == 365)
        #expect(policy.expiryDate(for: .secureNote) == nil)
        let date = policy.expiryDate(for: .login, from: Date(timeIntervalSince1970: 0))
        #expect(Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: date!).day == 180)
    }

    @Test func roundTripsAndRejectsUnknownValues() throws {
        let settings = SettingsRepository(dbQueue: try AppDatabase.inMemory().dbQueue)
        var policy = ExpiryPolicy()
        policy.ttlDays[.apiKey] = 30
        policy.ttlDays[.envSet] = 90
        try policy.save(to: settings)
        #expect(try ExpiryPolicy.load(from: settings) == policy)
        try settings.set("expiry.ttlDays.apiKey", "42")
        #expect(try ExpiryPolicy.load(from: settings).ttl(for: .apiKey) == 90)
    }
}

@Suite struct ExpiryMilestonesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ title: String, daysLeft: Double?, deleted: Bool = false) -> SecretItem {
        var i = makeItem(title, expiresAt: daysLeft.map { now.addingTimeInterval($0 * 86_400) })
        if deleted { i.deletedAt = now }
        return i
    }

    @Test func picksTheMostUrgentCrossedMilestoneOnly() {
        let items = [
            item("far", daysLeft: 30), item("two weeks", daysLeft: 13.5), item("week", daysLeft: 6),
            item("tomorrow", daysLeft: 0.5), item("today", daysLeft: -0.2), item("long gone", daysLeft: -5),
            item("never", daysLeft: nil), item("trashed", daysLeft: 1, deleted: true),
        ]
        let due = ExpiryMilestones.due(items, now: now) { _ in false }
        #expect(due.map { ($0.item.title, $0.milestone) }.map { "\($0.0):\($0.1)" } == ["two weeks:14", "week:7", "tomorrow:1", "today:0"])
    }

    @Test func alreadyNotifiedMilestonesAreSkippedAndMarkingCoversLessUrgentOnes() {
        let soon = item("soon", daysLeft: 3)
        let first = ExpiryMilestones.due([soon], now: now) { _ in false }
        #expect(first.map(\.milestone) == [7])
        let markers = ExpiryMilestones.markerKeysToSet(for: first[0])
        #expect(markers.count == 2, "7-day and 14-day markers")
        let again = ExpiryMilestones.due([soon], now: now) { markers.contains($0) }
        #expect(again.isEmpty)
        // Two days later it crosses the 1-day milestone, which is new.
        let later = ExpiryMilestones.due([soon], now: now.addingTimeInterval(2.5 * 86_400)) { markers.contains($0) }
        #expect(later.map(\.milestone) == [1])
    }

    @Test func rotationChangesTheMarkerKeys() {
        var i = item("k", daysLeft: 5)
        let before = ExpiryMilestones.due([i], now: now) { _ in false }[0].markerKey
        i.expiresAt = now.addingTimeInterval(90 * 86_400)
        i.expiresAt = now.addingTimeInterval(5 * 86_400 + 1)
        let after = ExpiryMilestones.due([i], now: now) { _ in false }[0].markerKey
        #expect(before != after)
    }
}
