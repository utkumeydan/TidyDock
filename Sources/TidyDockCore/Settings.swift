import Foundation

/// Which apps the "quit when the last window closes" rule applies to.
public enum QuitMode: String, Codable, CaseIterable, Sendable {
    /// Every app except the ones in `excludedBundleIDs`.
    case allExceptExcluded
    /// Only the apps in `includedBundleIDs`.
    case onlyIncluded
}

/// Actions that can be bound to a global keyboard shortcut.
public enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    case toggleSessionPause
    case toggleExcludeFrontmostApp
    case cleanNow
}

/// A global shortcut stored as a Carbon key code plus Carbon modifier flags.
public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

public struct TidySettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var mode: QuitMode
    public var excludedBundleIDs: [String]
    public var includedBundleIDs: [String]
    /// Seconds an app must stay windowless before it is quit.
    public var quitDelay: TimeInterval
    public var idleQuitEnabled: Bool
    /// Minutes an app may stay in the background before the idle rule quits it.
    public var idleMinutes: Int
    public var hotkeys: [HotkeyAction: Hotkey]
    /// Show a small "Undo" notice under the menu bar icon after each quit.
    public var showUndoNotice: Bool
    /// Offer to stop quitting apps the user keeps reopening.
    public var smartSuggestions: Bool

    public static let minimumQuitDelay: TimeInterval = 0
    public static let maximumQuitDelay: TimeInterval = 10
    public static let minimumIdleMinutes = 5
    public static let maximumIdleMinutes = 24 * 60

    /// Apps that usually run on purpose without a window.
    public static let defaultExcludedBundleIDs = [
        "com.apple.Music",
        "com.spotify.client",
        "com.apple.mail",
        "com.apple.MobileSMS",
        "com.apple.podcasts",
        "com.apple.ActivityMonitor",
    ]

    public static let `default` = TidySettings(
        isEnabled: true,
        mode: .allExceptExcluded,
        excludedBundleIDs: defaultExcludedBundleIDs,
        includedBundleIDs: [],
        quitDelay: 1,
        idleQuitEnabled: false,
        idleMinutes: 120,
        hotkeys: [:],
        showUndoNotice: true,
        smartSuggestions: true
    )

    public init(
        isEnabled: Bool,
        mode: QuitMode,
        excludedBundleIDs: [String],
        includedBundleIDs: [String],
        quitDelay: TimeInterval,
        idleQuitEnabled: Bool,
        idleMinutes: Int,
        hotkeys: [HotkeyAction: Hotkey],
        showUndoNotice: Bool = true,
        smartSuggestions: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.excludedBundleIDs = excludedBundleIDs
        self.includedBundleIDs = includedBundleIDs
        self.quitDelay = quitDelay
        self.idleQuitEnabled = idleQuitEnabled
        self.idleMinutes = idleMinutes
        self.hotkeys = hotkeys
        self.showUndoNotice = showUndoNotice
        self.smartSuggestions = smartSuggestions
        clamp()
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, mode, excludedBundleIDs, includedBundleIDs, quitDelay, idleQuitEnabled, idleMinutes, hotkeys
        case showUndoNotice, smartSuggestions
    }

    // Every field falls back to its default, so settings saved by an older
    // version keep loading after new fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TidySettings.default
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? d.isEnabled
        mode = (try? c.decodeIfPresent(QuitMode.self, forKey: .mode)) ?? d.mode
        excludedBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? d.excludedBundleIDs
        includedBundleIDs = try c.decodeIfPresent([String].self, forKey: .includedBundleIDs) ?? d.includedBundleIDs
        quitDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .quitDelay) ?? d.quitDelay
        idleQuitEnabled = try c.decodeIfPresent(Bool.self, forKey: .idleQuitEnabled) ?? d.idleQuitEnabled
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? d.idleMinutes
        let rawHotkeys = (try? c.decodeIfPresent([String: Hotkey].self, forKey: .hotkeys)) ?? [:]
        hotkeys = Dictionary(uniqueKeysWithValues: rawHotkeys.compactMap { key, value in
            HotkeyAction(rawValue: key).map { ($0, value) }
        })
        showUndoNotice = try c.decodeIfPresent(Bool.self, forKey: .showUndoNotice) ?? d.showUndoNotice
        smartSuggestions = try c.decodeIfPresent(Bool.self, forKey: .smartSuggestions) ?? d.smartSuggestions
        clamp()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(mode, forKey: .mode)
        try c.encode(excludedBundleIDs, forKey: .excludedBundleIDs)
        try c.encode(includedBundleIDs, forKey: .includedBundleIDs)
        try c.encode(quitDelay, forKey: .quitDelay)
        try c.encode(idleQuitEnabled, forKey: .idleQuitEnabled)
        try c.encode(idleMinutes, forKey: .idleMinutes)
        // Encode with string keys so the stored JSON is an object, not a flat array.
        try c.encode(Dictionary(uniqueKeysWithValues: hotkeys.map { ($0.key.rawValue, $0.value) }), forKey: .hotkeys)
        try c.encode(showUndoNotice, forKey: .showUndoNotice)
        try c.encode(smartSuggestions, forKey: .smartSuggestions)
    }

    private mutating func clamp() {
        quitDelay = min(max(quitDelay, Self.minimumQuitDelay), Self.maximumQuitDelay)
        idleMinutes = min(max(idleMinutes, Self.minimumIdleMinutes), Self.maximumIdleMinutes)
    }

    /// Whether the app is covered by the current mode and lists.
    public func isEligible(bundleID: String) -> Bool {
        switch mode {
        case .allExceptExcluded: return !excludedBundleIDs.contains(bundleID)
        case .onlyIncluded: return includedBundleIDs.contains(bundleID)
        }
    }

    /// The list the "never quit this app" toggle edits in the current mode.
    public func isNeverQuit(bundleID: String) -> Bool {
        !isEligible(bundleID: bundleID)
    }

    /// Flips an app between "quit automatically" and "never quit" in the current mode.
    public mutating func toggleNeverQuit(bundleID: String) {
        switch mode {
        case .allExceptExcluded:
            if let index = excludedBundleIDs.firstIndex(of: bundleID) {
                excludedBundleIDs.remove(at: index)
            } else {
                excludedBundleIDs.append(bundleID)
            }
        case .onlyIncluded:
            if let index = includedBundleIDs.firstIndex(of: bundleID) {
                includedBundleIDs.remove(at: index)
            } else {
                includedBundleIDs.append(bundleID)
            }
        }
    }
}
