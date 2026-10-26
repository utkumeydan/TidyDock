import Foundation
import Testing
@testable import TidyDockCore

@Suite struct SettingsTests {
    @Test func roundTripsThroughJSON() throws {
        var s = TidySettings.default
        s.mode = .onlyIncluded
        s.includedBundleIDs = ["com.example.A"]
        s.idleQuitEnabled = true
        s.hotkeys[.toggleSessionPause] = Hotkey(keyCode: 35, carbonModifiers: 0x0900)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(TidySettings.self, from: data) == s)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let data = Data(#"{"isEnabled": false}"#.utf8)
        let s = try JSONDecoder().decode(TidySettings.self, from: data)
        #expect(s.isEnabled == false)
        #expect(s.excludedBundleIDs == TidySettings.defaultExcludedBundleIDs)
        #expect(s.quitDelay == 1)
        #expect(s.showUndoNotice && s.smartSuggestions)
    }

    @Test func unknownModeAndHotkeyNamesAreIgnored() throws {
        let data = Data(#"{"mode": "someFutureMode", "hotkeys": {"futureAction": {"keyCode": 1, "carbonModifiers": 256}}}"#.utf8)
        let s = try JSONDecoder().decode(TidySettings.self, from: data)
        #expect(s.mode == .allExceptExcluded)
        #expect(s.hotkeys.isEmpty)
    }

    @Test func outOfRangeValuesAreClamped() throws {
        let data = Data(#"{"quitDelay": 99, "idleMinutes": 1}"#.utf8)
        let s = try JSONDecoder().decode(TidySettings.self, from: data)
        #expect(s.quitDelay == TidySettings.maximumQuitDelay)
        #expect(s.idleMinutes == TidySettings.minimumIdleMinutes)
    }
}
