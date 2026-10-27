import Testing
@testable import KeyCellarCore

@Suite struct AutoLockPolicyTests {
    @Test func defaultsAreTheSafeSide() {
        let p = AutoLockPolicy()
        #expect(p.idleTimeout == .fiveMinutes)
        #expect(p.shouldLock(on: .willSleep))
        #expect(p.shouldLock(on: .screenLocked))
        #expect(!p.shouldLock(on: .appHidden))
    }

    @Test func idleLocksAtTheThresholdAndNeverMeansNever() {
        let p = AutoLockPolicy(idleTimeout: .oneMinute)
        #expect(!p.shouldLock(on: .idle(seconds: 59)))
        #expect(p.shouldLock(on: .idle(seconds: 60)))
        #expect(!AutoLockPolicy(idleTimeout: .never).shouldLock(on: .idle(seconds: 1_000_000)))
    }

    @Test func eachSwitchGatesItsEvent() {
        let off = AutoLockPolicy(lockOnSleep: false, lockOnScreenLock: false, lockWhenHidden: true)
        #expect(!off.shouldLock(on: .willSleep))
        #expect(!off.shouldLock(on: .screenLocked))
        #expect(off.shouldLock(on: .appHidden))
    }

    @Test func roundTripsThroughSettings() throws {
        let settings = SettingsRepository(dbQueue: try AppDatabase.inMemory().dbQueue)
        #expect(try AutoLockPolicy.load(from: settings) == AutoLockPolicy())
        let custom = AutoLockPolicy(idleTimeout: .thirtyMinutes, lockOnSleep: false, lockOnScreenLock: true, lockWhenHidden: true)
        try custom.save(to: settings)
        #expect(try AutoLockPolicy.load(from: settings) == custom)
    }

    @Test func garbageInSettingsFallsBackToDefaults() throws {
        let settings = SettingsRepository(dbQueue: try AppDatabase.inMemory().dbQueue)
        try settings.set("autoLock.idleSeconds", "42")
        #expect(try AutoLockPolicy.load(from: settings).idleTimeout == .fiveMinutes)
    }
}
