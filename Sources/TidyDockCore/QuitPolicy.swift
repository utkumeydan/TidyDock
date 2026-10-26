import Foundation

/// What TidyDock remembers about one running app between checks.
public struct AppRecord: Equatable, Sendable {
    public let pid: Int32
    public let bundleID: String?
    /// `true` for apps that show in the Dock. Menu bar and background apps are never touched.
    public var isRegularApp: Bool
    public var isHidden: Bool
    public var isFrontmost: Bool
    public private(set) var windowState: WindowState = .unknown
    /// Set the first time the app is seen with a window. Apps that start
    /// without one (login items, helpers, web app shims) are left alone.
    public private(set) var hasEverHadWindow = false
    public private(set) var windowlessSince: Date?
    public private(set) var lastActiveAt: Date
    public private(set) var quitRequestedAt: Date?

    public init(pid: Int32, bundleID: String?, isRegularApp: Bool, isHidden: Bool = false, isFrontmost: Bool = false, now: Date) {
        self.pid = pid
        self.bundleID = bundleID
        self.isRegularApp = isRegularApp
        self.isHidden = isHidden
        self.isFrontmost = isFrontmost
        self.lastActiveAt = now
    }

    public mutating func update(windowState newState: WindowState, now: Date) {
        windowState = newState
        switch newState {
        case .count(let n) where n > 0:
            hasEverHadWindow = true
            windowlessSince = nil
            // A window is back, so a quit we asked for earlier was cancelled
            // (for example from a "save changes?" dialog).
            quitRequestedAt = nil
        case .count:
            if windowlessSince == nil { windowlessSince = now }
        case .unknown:
            // Start the countdown again once we can see the windows.
            windowlessSince = nil
        }
    }

    public mutating func markActive(now: Date) {
        lastActiveAt = now
    }

    public mutating func markQuitRequested(now: Date) {
        quitRequestedAt = now
        // If the app refuses to quit, the idle timer starts over instead of
        // asking again on the next check.
        lastActiveAt = now
    }
}

public enum QuitReason: String, Equatable, Sendable {
    case noWindows
    case idle
    /// The user chose "Clean Up Now".
    case cleanUp
}

public enum QuitDecision: Equatable, Sendable {
    case keep
    /// Check again at this time.
    case recheck(at: Date)
    case quit(QuitReason)
}

public struct PolicyContext: Equatable, Sendable {
    public var ownBundleID: String?
    public var isSessionPaused: Bool

    public init(ownBundleID: String?, isSessionPaused: Bool) {
        self.ownBundleID = ownBundleID
        self.isSessionPaused = isSessionPaused
    }
}

public enum QuitPolicy {
    /// System apps that must never be quit, whatever the settings say.
    public static let protectedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
    ]

    public static func isProtected(bundleID: String, context: PolicyContext) -> Bool {
        bundleID == context.ownBundleID || protectedBundleIDs.contains(bundleID)
    }

    /// Whether "Clean Up Now" may quit this app: a Dock app with no windows
    /// that the settings don't protect. Unlike the automatic rule this also
    /// covers apps that never had a window, since the user asked for it.
    public static func isCleanable(_ app: AppRecord, settings: TidySettings, context: PolicyContext) -> Bool {
        guard let bundleID = app.bundleID,
              app.isRegularApp,
              !app.isHidden,
              !isProtected(bundleID: bundleID, context: context),
              app.quitRequestedAt == nil,
              app.windowState == .count(0),
              settings.isEligible(bundleID: bundleID)
        else { return false }
        return true
    }

    public static func decide(_ app: AppRecord, settings: TidySettings, context: PolicyContext, now: Date) -> QuitDecision {
        guard let bundleID = app.bundleID,
              app.isRegularApp,
              !isProtected(bundleID: bundleID, context: context),
              settings.isEnabled,
              !context.isSessionPaused,
              app.quitRequestedAt == nil,
              settings.isEligible(bundleID: bundleID)
        else { return .keep }

        var nextCheck: Date?

        if app.hasEverHadWindow, !app.isHidden, app.windowState == .count(0), let since = app.windowlessSince {
            let deadline = since.addingTimeInterval(settings.quitDelay)
            if now >= deadline { return .quit(.noWindows) }
            nextCheck = deadline
        }

        if settings.idleQuitEnabled, !app.isFrontmost {
            let deadline = app.lastActiveAt.addingTimeInterval(TimeInterval(settings.idleMinutes) * 60)
            if now >= deadline { return .quit(.idle) }
            nextCheck = nextCheck.map { min($0, deadline) } ?? deadline
        }

        return nextCheck.map { .recheck(at: $0) } ?? .keep
    }
}
