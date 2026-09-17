import SwiftUI
import Testing
@testable import DKB_Secret

@Suite struct ThemePreferenceTests {
    @Test func systemHandsControlBackToTheOS() {
        #expect(ThemePreference.system.colorScheme == nil)
        #expect(ThemePreference.light.colorScheme == .light)
        #expect(ThemePreference.dark.colorScheme == .dark)
    }
}
