import Foundation

/// How many apps TidyDock quit and how much memory that freed, per day and in total.
public struct UsageStats: Codable, Equatable, Sendable {
    public struct Totals: Codable, Equatable, Sendable {
        public var quits: Int = 0
        public var bytes: Int64 = 0

        public init(quits: Int = 0, bytes: Int64 = 0) {
            self.quits = quits
            self.bytes = bytes
        }

        mutating func add(bytes: Int64) {
            quits += 1
            self.bytes += max(bytes, 0)
        }

        static func + (a: Totals, b: Totals) -> Totals {
            Totals(quits: a.quits + b.quits, bytes: a.bytes + b.bytes)
        }
    }

    /// Keyed by day ("2026-10-26"), kept for `retainedDays`.
    public private(set) var days: [String: Totals] = [:]
    public private(set) var allTime = Totals()

    static let retainedDays = 31

    public init() {}

    public mutating func record(bytes: Int64, at date: Date, calendar: Calendar = .current) {
        allTime.add(bytes: bytes)
        days[Self.key(for: date, calendar: calendar), default: Totals()].add(bytes: bytes)
        prune(now: date, calendar: calendar)
    }

    public func today(now: Date, calendar: Calendar = .current) -> Totals {
        days[Self.key(for: now, calendar: calendar)] ?? Totals()
    }

    /// Today and the six days before it.
    public func lastSevenDays(now: Date, calendar: Calendar = .current) -> Totals {
        (0..<7).reduce(Totals()) { sum, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return sum }
            return sum + (days[Self.key(for: day, calendar: calendar)] ?? Totals())
        }
    }

    private mutating func prune(now: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retainedDays, to: now) else { return }
        let oldest = Self.key(for: cutoff, calendar: calendar)
        // Keys sort in date order, so a string comparison is enough.
        days = days.filter { $0.key > oldest }
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Notices apps the user keeps reopening right after TidyDock quits them,
/// so TidyDock can offer to stop quitting them.
public struct SuggestionTracker: Codable, Equatable, Sendable {
    /// A relaunch within this many seconds of a quit counts as "the user wanted it".
    public static let reopenWindow: TimeInterval = 90
    /// How many quick reopens it takes before suggesting.
    public static let threshold = 2

    public private(set) var quickReopens: [String: Int] = [:]
    /// Apps we already asked about, whatever the answer was.
    public private(set) var asked: Set<String> = []

    public init() {}

    /// Returns `true` when TidyDock should now suggest never quitting this app.
    public mutating func appLaunched(bundleID: String, quitByUsAt: Date?, now: Date) -> Bool {
        guard let quitAt = quitByUsAt, now.timeIntervalSince(quitAt) <= Self.reopenWindow, !asked.contains(bundleID) else {
            return false
        }
        quickReopens[bundleID, default: 0] += 1
        return quickReopens[bundleID, default: 0] >= Self.threshold
    }

    public mutating func markAsked(bundleID: String) {
        asked.insert(bundleID)
        quickReopens[bundleID] = nil
    }
}
