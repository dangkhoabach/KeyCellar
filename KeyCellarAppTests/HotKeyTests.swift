import AppKit
import Carbon.HIToolbox
import KeyCellarCore
import Testing
@testable import KeyCellar

@Suite struct HotKeyTests {
    @Test func defaultIsOptionCommandS() {
        #expect(HotKey.default.displayString == "⌥⌘S")
    }

    @Test func modifierOrderAndSpecialKeys() {
        let all = HotKey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(all.displayString == "⌃⌥⇧⌘Space")
        #expect(HotKey(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(cmdKey)).displayString == "⌘F5")
    }

    @Test func aPressWithoutCommandOptionOrControlIsRejected() {
        let plain = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
                                     context: nil, characters: "S", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: UInt16(kVK_ANSI_S))!
        #expect(HotKey(event: plain) == nil)
        let ok = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option, .command], timestamp: 0, windowNumber: 0,
                                  context: nil, characters: "s", charactersIgnoringModifiers: "s", isARepeat: false, keyCode: UInt16(kVK_ANSI_S))!
        #expect(HotKey(event: ok) == .default)
    }

    @Test func roundTripsThroughSettings() throws {
        let settings = SettingsRepository(dbQueue: try AppDatabase.inMemory().dbQueue)
        #expect(HotKey.load(from: settings) == .default)
        let custom = HotKey(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(controlKey | cmdKey))
        custom.save(to: settings)
        #expect(HotKey.load(from: settings) == custom)
    }
}
