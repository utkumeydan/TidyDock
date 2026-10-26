import AppKit
import TidyDockCore

/// Shows one screen with sample data, for README and website screenshots.
///
///     TIDYDOCK_SCREENSHOT=general TIDYDOCK_APPEARANCE=light TidyDock.app/Contents/MacOS/TidyDock -AppleLanguages '(tr)'
///
/// In this mode TidyDock doesn't watch or quit any app, and nothing it shows is saved.
enum ScreenshotMode {
    enum Scene: String {
        case welcome, permission, setup, general, apps, shortcuts, about, notice, suggestion, menu

        var settingsTab: Int {
            switch self {
            case .apps: return 1
            case .shortcuts: return 2
            case .about: return 3
            default: return 0
            }
        }
    }

    static let scene: Scene? = ProcessInfo.processInfo.environment["TIDYDOCK_SCREENSHOT"].flatMap(Scene.init(rawValue:))

    /// A throwaway defaults domain, emptied on every launch.
    static let defaults: UserDefaults? = {
        guard scene != nil else { return nil }
        let name = "io.github.utkumeydan.TidyDock.screenshots"
        let defaults = UserDefaults(suiteName: name)
        defaults?.removePersistentDomain(forName: name)
        return defaults
    }()

    static var sampleEntry: QuitEntry {
        entry("com.apple.Safari", minutesAgo: 0, bytes: 1_240_000_000, reason: .noWindows)
    }

    static func loadSampleData(into log: QuitLog) {
        switch ProcessInfo.processInfo.environment["TIDYDOCK_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }

        let now = Date()
        var stats = UsageStats()
        // Older history only counts toward the all-time total.
        for i in 0..<389 {
            stats.record(bytes: 180_000_000 + Int64(i % 7) * 40_000_000, at: now.addingTimeInterval(-40 * 86_400))
        }
        // This week, with today last.
        let week: [(daysAgo: Double, bytes: Int64)] = [
            (6, 310_000_000), (6, 95_000_000), (5, 640_000_000), (5, 120_000_000), (4, 220_000_000),
            (4, 85_000_000), (3, 410_000_000), (3, 150_000_000), (3, 60_000_000), (2, 280_000_000),
            (2, 190_000_000), (2, 75_000_000), (1, 330_000_000), (1, 140_000_000), (1, 90_000_000),
            (1, 55_000_000), (1, 210_000_000), (1, 70_000_000),
        ]
        for item in week {
            stats.record(bytes: item.bytes, at: now.addingTimeInterval(-item.daysAgo * 86_400))
        }
        let recent = [
            entry("com.apple.Safari", minutesAgo: 2, bytes: 1_240_000_000, reason: .noWindows),
            entry("com.apple.Preview", minutesAgo: 9, bytes: 186_000_000, reason: .noWindows),
            entry("com.apple.TextEdit", minutesAgo: 26, bytes: 64_000_000, reason: .noWindows),
            entry("com.apple.Notes", minutesAgo: 71, bytes: 142_000_000, reason: .idle),
            entry("com.apple.iCal", minutesAgo: 180, bytes: 98_000_000, reason: .cleanUp),
        ]
        for item in recent {
            stats.record(bytes: item.bytes, at: item.date)
        }
        log.loadSample(entries: recent, stats: stats)
    }

    private static func entry(_ bundleID: String, minutesAgo: Double, bytes: Int64, reason: QuitReason) -> QuitEntry {
        let info = AppInfo(bundleID: bundleID)
        return QuitEntry(bundleID: bundleID, name: info.name, bundleURL: info.url, reason: reason,
                         date: Date().addingTimeInterval(-minutesAgo * 60), bytes: bytes)
    }
}
