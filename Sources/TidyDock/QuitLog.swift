import AppKit
import os
import TidyDockCore

let log = Logger(subsystem: "io.github.utkumeydan.TidyDock", category: "general")

struct QuitEntry {
    let bundleID: String
    let name: String
    let bundleURL: URL?
    let reason: QuitReason
    let date: Date
    /// Memory the app (with its helpers) was using right before it quit.
    let bytes: Int64
}

/// The most recent apps TidyDock quit, the saved statistics, and the
/// "you keep reopening this app" tracker.
final class QuitLog {
    static let didChange = Notification.Name("TidyDockQuitLogDidChange")
    /// Posted once per quit or clean-up with `entriesKey` holding `[QuitEntry]`.
    static let didQuit = Notification.Name("TidyDockDidQuit")
    static let entriesKey = "entries"

    private let limit = 15
    private let defaults: UserDefaults
    private let statsKey = "stats.v1"
    private let legacyTotalKey = "stats.totalQuits"
    private let trackerKey = "suggestions.v1"

    private(set) var entries: [QuitEntry] = []
    private(set) var stats: UsageStats
    private var tracker: SuggestionTracker

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stats = defaults.data(forKey: statsKey).flatMap { try? JSONDecoder().decode(UsageStats.self, from: $0) } ?? UsageStats()
        tracker = defaults.data(forKey: trackerKey).flatMap { try? JSONDecoder().decode(SuggestionTracker.self, from: $0) } ?? SuggestionTracker()
        defaults.removeObject(forKey: legacyTotalKey)
    }

    func record(_ batch: [QuitEntry]) {
        guard !batch.isEmpty else { return }
        for entry in batch {
            stats.record(bytes: entry.bytes, at: entry.date)
            entries.insert(entry, at: 0)
            log.info("Quit \(entry.bundleID, privacy: .public) (\(entry.reason.rawValue, privacy: .public), \(entry.bytes) bytes)")
        }
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
        NotificationCenter.default.post(name: Self.didChange, object: self)
        NotificationCenter.default.post(name: Self.didQuit, object: self, userInfo: [Self.entriesKey: batch])
    }

    /// Replaces what the menu and Settings show, without saving (screenshot mode).
    func loadSample(entries: [QuitEntry], stats: UsageStats) {
        self.entries = entries
        self.stats = stats
    }

    /// Call when an app launches. Returns `true` when it's time to suggest never quitting it.
    func appLaunched(bundleID: String, now: Date) -> Bool {
        let quitAt = entries.first { $0.bundleID == bundleID && $0.reason != .cleanUp }?.date
        let suggest = tracker.appLaunched(bundleID: bundleID, quitByUsAt: quitAt, now: now)
        save()
        return suggest
    }

    func markSuggested(bundleID: String) {
        tracker.markAsked(bundleID: bundleID)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stats) { defaults.set(data, forKey: statsKey) }
        if let data = try? JSONEncoder().encode(tracker) { defaults.set(data, forKey: trackerKey) }
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    /// "5 apps · 1.2 GB"
    static func summary(_ totals: UsageStats.Totals) -> String {
        let apps = totals.quits == 1 ? L("1 app") : L("%d apps", totals.quits)
        return totals.bytes > 0 ? "\(apps) · \(bytes(totals.bytes))" : apps
    }
}
