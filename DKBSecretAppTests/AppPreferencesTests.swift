import DKBSecretCore
import Testing
@testable import DKB_Secret

@MainActor
@Suite struct AppPreferencesTests {
    @Test func defaultsThenPersistsEveryChange() throws {
        let settings = SettingsRepository(dbQueue: try AppDatabase.inMemory().dbQueue)
        let prefs = AppPreferences(settings: settings)
        #expect(prefs.clipboardSeconds == 45)
        #expect(prefs.revealSeconds == 30)
        #expect(prefs.authReuseSeconds == 30)
        #expect(prefs.autoLock == AutoLockPolicy())

        var pushed: [Int] = []
        prefs.onAuthReuseChanged = { pushed.append($0) }
        prefs.clipboardSeconds = 15
        prefs.revealSeconds = 60
        prefs.authReuseSeconds = 0
        prefs.autoLock.idleTimeout = .never
        prefs.autoLock.lockWhenHidden = true

        let reloaded = AppPreferences(settings: settings)
        #expect(reloaded.clipboardSeconds == 15)
        #expect(reloaded.revealSeconds == 60)
        #expect(reloaded.authReuseSeconds == 0)
        #expect(reloaded.autoLock.idleTimeout == .never)
        #expect(reloaded.autoLock.lockWhenHidden)
        #expect(pushed == [0])
    }

    @Test func rejectsValuesOutsideTheOfferedChoices() throws {
        let settings = SettingsRepository(dbQueue: try AppDatabase.inMemory().dbQueue)
        try settings.set(AppPreferences.Keys.clipboard, "0")
        try settings.set(AppPreferences.Keys.reveal, "99999")
        try settings.set(AppPreferences.Keys.authReuse, "abc")
        let prefs = AppPreferences(settings: settings)
        #expect(prefs.clipboardSeconds == 45)
        #expect(prefs.revealSeconds == 30)
        #expect(prefs.authReuseSeconds == 30)
    }
}
