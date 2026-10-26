import Foundation
import Testing
@testable import TidyDockCore

private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
    return c
}()

private func day(_ d: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
}

@Suite struct UsageStatsTests {
    @Test func countsTodayWeekAndAllTime() {
        var stats = UsageStats()
        stats.record(bytes: 100, at: day(10), calendar: calendar)
        stats.record(bytes: 200, at: day(20), calendar: calendar)
        stats.record(bytes: 300, at: day(26, hour: 9), calendar: calendar)
        stats.record(bytes: 400, at: day(26, hour: 18), calendar: calendar)

        let now = day(26, hour: 20)
        #expect(stats.today(now: now, calendar: calendar) == .init(quits: 2, bytes: 700))
        // The 20th through the 26th.
        #expect(stats.lastSevenDays(now: now, calendar: calendar) == .init(quits: 3, bytes: 900))
        #expect(stats.allTime == .init(quits: 4, bytes: 1000))
    }

    @Test func dropsOldDaysButKeepsTheTotal() {
        var stats = UsageStats()
        stats.record(bytes: 100, at: day(1), calendar: calendar)
        let later = calendar.date(byAdding: .day, value: 40, to: day(1))!
        stats.record(bytes: 50, at: later, calendar: calendar)
        #expect(stats.days.count == 1)
        #expect(stats.allTime == .init(quits: 2, bytes: 150))
    }

    @Test func negativeSizesCountAsZero() {
        var stats = UsageStats()
        stats.record(bytes: -5, at: day(3), calendar: calendar)
        #expect(stats.allTime == .init(quits: 1, bytes: 0))
    }

    @Test func roundTripsThroughJSON() throws {
        var stats = UsageStats()
        stats.record(bytes: 123, at: day(5), calendar: calendar)
        let decoded = try JSONDecoder().decode(UsageStats.self, from: JSONEncoder().encode(stats))
        #expect(decoded == stats)
    }
}

@Suite struct SuggestionTrackerTests {
    let quitAt = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func suggestsAfterTwoQuickReopens() {
        var tracker = SuggestionTracker()
        do { let result = tracker.appLaunched(bundleID: "com.spotify.client", quitByUsAt: quitAt, now: quitAt.addingTimeInterval(20)); #expect(!result) }
        do { let result = tracker.appLaunched(bundleID: "com.spotify.client", quitByUsAt: quitAt.addingTimeInterval(500), now: quitAt.addingTimeInterval(530)); #expect(result) }
    }

    @Test func slowReopensAndAppsWeDidNotQuitDoNotCount() {
        var tracker = SuggestionTracker()
        for _ in 0..<5 {
            do { let result = tracker.appLaunched(bundleID: "a", quitByUsAt: quitAt, now: quitAt.addingTimeInterval(600)); #expect(!result) }
            do { let result = tracker.appLaunched(bundleID: "a", quitByUsAt: nil, now: quitAt); #expect(!result) }
        }
    }

    @Test func asksOnlyOnce() {
        var tracker = SuggestionTracker()
        _ = tracker.appLaunched(bundleID: "a", quitByUsAt: quitAt, now: quitAt.addingTimeInterval(1))
        do { let result = tracker.appLaunched(bundleID: "a", quitByUsAt: quitAt, now: quitAt.addingTimeInterval(2)); #expect(result) }
        tracker.markAsked(bundleID: "a")
        for _ in 0..<3 {
            do { let result = tracker.appLaunched(bundleID: "a", quitByUsAt: quitAt, now: quitAt.addingTimeInterval(3)); #expect(!result) }
        }
    }
}

@Suite struct CleanUpRule {
    let context = PolicyContext(ownBundleID: "io.github.utkumeydan.TidyDock", isSessionPaused: true)
    let now = Date(timeIntervalSinceReferenceDate: 0)

    func app(_ id: String = "com.example.App", windows: WindowState) -> AppRecord {
        var record = AppRecord(pid: 1, bundleID: id, isRegularApp: true, now: now)
        record.update(windowState: windows, now: now)
        return record
    }

    @Test func cleansWindowlessAppsEvenIfTheyNeverHadAWindowOrArePaused() {
        #expect(QuitPolicy.isCleanable(app(windows: .count(0)), settings: .default, context: context))
    }

    @Test func keepsAppsWithWindowsOrUnknownState() {
        #expect(!QuitPolicy.isCleanable(app(windows: .count(2)), settings: .default, context: context))
        #expect(!QuitPolicy.isCleanable(app(windows: .unknown), settings: .default, context: context))
    }

    @Test func respectsListsProtectionAndHiddenApps() {
        #expect(!QuitPolicy.isCleanable(app("com.apple.Music", windows: .count(0)), settings: .default, context: context))
        #expect(!QuitPolicy.isCleanable(app("com.apple.finder", windows: .count(0)), settings: .default, context: context))
        var hidden = app(windows: .count(0))
        hidden.isHidden = true
        #expect(!QuitPolicy.isCleanable(hidden, settings: .default, context: context))
    }
}
