import SwiftUI
import Testing
@testable import KeyCellar

@Suite struct ThemePreferenceTests {
    @Test func systemHandsControlBackToTheOS() {
        #expect(ThemePreference.system.colorScheme == nil)
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
    }
}
