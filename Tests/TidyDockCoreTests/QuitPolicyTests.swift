import Foundation
import Testing
@testable import TidyDockCore

private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let context = PolicyContext(ownBundleID: "io.github.utkumeydan.TidyDock", isSessionPaused: false)

private func record(_ bundleID: String = "com.example.Editor", regular: Bool = true) -> AppRecord {
    AppRecord(pid: 42, bundleID: bundleID, isRegularApp: regular, now: start)
}

/// An app that had a window and closed it at `start`.
private func closedApp(_ bundleID: String = "com.example.Editor") -> AppRecord {
    var app = record(bundleID)
    app.update(windowState: .count(1), now: start.addingTimeInterval(-10))
    app.update(windowState: .count(0), now: start)
    return app
}

@Suite struct NoWindowRule {
    let settings = TidySettings.default // 1 second delay

    @Test func waitsForTheDelayThenQuits() {
        let app = closedApp()
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(0.5)) == .recheck(at: start.addingTimeInterval(1)))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(1)) == .quit(.noWindows))
    }

    @Test func zeroDelayQuitsRightAway() {
        var s = settings
        s.quitDelay = 0
        #expect(QuitPolicy.decide(closedApp(), settings: s, context: context, now: start) == .quit(.noWindows))
    }

    @Test func neverQuitsAnAppThatNeverHadAWindow() {
        // Login items, helpers and web app shims start without windows.
        var app = record()
        app.update(windowState: .count(0), now: start)
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(60)) == .keep)
    }

    @Test func aNewWindowCancelsTheCountdown() {
        // Closing a tab or swapping documents briefly leaves zero windows.
        var app = closedApp()
        app.update(windowState: .count(1), now: start.addingTimeInterval(0.3))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(5)) == .keep)
    }

    @Test func unknownWindowStateNeverQuits() {
        var app = closedApp()
        app.update(windowState: .unknown, now: start.addingTimeInterval(0.5))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(5)) == .keep)
    }

    @Test func countdownRestartsAfterAnUnknownState() {
        var app = closedApp()
        app.update(windowState: .unknown, now: start.addingTimeInterval(0.5))
        app.update(windowState: .count(0), now: start.addingTimeInterval(3))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(3.5)) == .recheck(at: start.addingTimeInterval(4)))
    }

    @Test func hiddenAppsAreKept() {
        var app = closedApp()
        app.isHidden = true
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(5)) == .keep)
    }

    @Test func menuBarAndBackgroundAppsAreNeverTouched() {
        var app = closedApp()
        app.isRegularApp = false
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(5)) == .keep)
    }

    @Test func protectedAndOwnAppsAreKept() {
        for id in ["com.apple.finder", "io.github.utkumeydan.TidyDock"] {
            #expect(QuitPolicy.decide(closedApp(id), settings: settings, context: context, now: start.addingTimeInterval(5)) == .keep)
        }
    }

    @Test func askingOnceIsEnough() {
        var app = closedApp()
        app.markQuitRequested(now: start.addingTimeInterval(1))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(5)) == .keep)
    }

    @Test func aCancelledQuitIsRetriedAfterTheNextClose() {
        // The user pressed "Cancel" on a save dialog, kept working, then closed the window again.
        var app = closedApp()
        app.markQuitRequested(now: start.addingTimeInterval(1))
        app.update(windowState: .count(1), now: start.addingTimeInterval(2))
        app.update(windowState: .count(0), now: start.addingTimeInterval(20))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(21)) == .quit(.noWindows))
    }
}

@Suite struct SwitchesAndLists {
    @Test func disabledOrPausedKeepsEverything() {
        var off = TidySettings.default
        off.isEnabled = false
        #expect(QuitPolicy.decide(closedApp(), settings: off, context: context, now: start.addingTimeInterval(5)) == .keep)

        let paused = PolicyContext(ownBundleID: nil, isSessionPaused: true)
        #expect(QuitPolicy.decide(closedApp(), settings: .default, context: paused, now: start.addingTimeInterval(5)) == .keep)
    }

    @Test func excludedAppsAreKept() {
        var s = TidySettings.default
        s.excludedBundleIDs = ["com.example.Editor"]
        #expect(QuitPolicy.decide(closedApp(), settings: s, context: context, now: start.addingTimeInterval(5)) == .keep)
    }

    @Test func onlyIncludedModeQuitsJustTheListedApps() {
        var s = TidySettings.default
        s.mode = .onlyIncluded
        s.includedBundleIDs = ["com.example.Listed"]
        #expect(QuitPolicy.decide(closedApp(), settings: s, context: context, now: start.addingTimeInterval(5)) == .keep)
        #expect(QuitPolicy.decide(closedApp("com.example.Listed"), settings: s, context: context, now: start.addingTimeInterval(5)) == .quit(.noWindows))
    }

    @Test func toggleNeverQuitEditsTheListForTheCurrentMode() {
        var s = TidySettings.default
        s.toggleNeverQuit(bundleID: "com.example.Editor")
        #expect(s.excludedBundleIDs.contains("com.example.Editor"))
        #expect(s.isNeverQuit(bundleID: "com.example.Editor"))
        s.toggleNeverQuit(bundleID: "com.example.Editor")
        #expect(!s.isNeverQuit(bundleID: "com.example.Editor"))

        s.mode = .onlyIncluded
        #expect(s.isNeverQuit(bundleID: "com.example.Editor"))
        s.toggleNeverQuit(bundleID: "com.example.Editor")
        #expect(s.includedBundleIDs == ["com.example.Editor"])
        #expect(!s.isNeverQuit(bundleID: "com.example.Editor"))
    }

    @Test func nonEnglishBundleIDsMatchExactly() {
        // Swift Quit matched on encoded paths and broke for names like this.
        var s = TidySettings.default
        s.excludedBundleIDs = ["com.örnek.Düzenleyici"]
        #expect(QuitPolicy.decide(closedApp("com.örnek.Düzenleyici"), settings: s, context: context, now: start.addingTimeInterval(5)) == .keep)
    }
}

@Suite struct IdleRule {
    var settings: TidySettings {
        var s = TidySettings.default
        s.idleQuitEnabled = true
        s.idleMinutes = 30
        return s
    }

    /// A background app that still has a window open.
    func openApp() -> AppRecord {
        var app = record()
        app.update(windowState: .count(1), now: start)
        return app
    }

    @Test func quitsAfterTheIdleTime() {
        let app = openApp()
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(29 * 60)) == .recheck(at: start.addingTimeInterval(30 * 60)))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(30 * 60)) == .quit(.idle))
    }

    @Test func offByDefault() {
        #expect(QuitPolicy.decide(openApp(), settings: .default, context: context, now: start.addingTimeInterval(24 * 3600)) == .keep)
    }

    @Test func theFrontAppIsNeverIdle() {
        var app = openApp()
        app.isFrontmost = true
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(24 * 3600)) == .keep)
    }

    @Test func usingTheAppResetsTheTimer() {
        var app = openApp()
        app.markActive(now: start.addingTimeInterval(20 * 60))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(30 * 60)) == .recheck(at: start.addingTimeInterval(50 * 60)))
    }

    @Test func aRefusedIdleQuitIsNotRepeatedImmediately() {
        var app = openApp()
        app.markQuitRequested(now: start.addingTimeInterval(30 * 60))
        // The app showed a save dialog; the window is still there.
        app.update(windowState: .count(1), now: start.addingTimeInterval(30 * 60 + 1))
        #expect(QuitPolicy.decide(app, settings: settings, context: context, now: start.addingTimeInterval(31 * 60)) == .recheck(at: start.addingTimeInterval(60 * 60)))
    }

    @Test func picksTheEarlierRecheck() {
        var s = settings
        s.quitDelay = 5
        let app = closedApp()
        #expect(QuitPolicy.decide(app, settings: s, context: context, now: start.addingTimeInterval(1)) == .recheck(at: start.addingTimeInterval(5)))
    }
}
