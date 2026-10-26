import Foundation

/// A window as reported by the Accessibility API. It only lists windows on
/// the current Space, but includes minimized ones.
public struct AccessibilityWindow: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var isMinimized: Bool
    public var width: Double
    public var height: Double

    public init(role: String?, subrole: String?, isMinimized: Bool, width: Double, height: Double) {
        self.role = role
        self.subrole = subrole
        self.isMinimized = isMinimized
        self.width = width
        self.height = height
    }
}

/// A window as reported by the window server (`CGWindowListCopyWindowInfo`).
/// It sees every Space, but also lists invisible helper windows.
public struct ServerWindow: Equatable, Sendable {
    public var layer: Int
    public var alpha: Double
    public var width: Double
    public var height: Double
    public var isOnScreen: Bool
    /// Whether the window belongs to any Space. `nil` when that could not be
    /// determined. Windows an app has ordered out belong to no Space.
    public var isOnAnySpace: Bool?
    /// Whether the window is placed on its Space. Some apps (Microsoft Office,
    /// TidyDock's own settings) keep a closed window that still belongs to a
    /// Space but is ordered out. `nil` when that could not be determined.
    public var isOrderedIn: Bool?

    public init(layer: Int, alpha: Double, width: Double, height: Double, isOnScreen: Bool, isOnAnySpace: Bool?, isOrderedIn: Bool? = nil) {
        self.layer = layer
        self.alpha = alpha
        self.width = width
        self.height = height
        self.isOnScreen = isOnScreen
        self.isOnAnySpace = isOnAnySpace
        self.isOrderedIn = isOrderedIn
    }
}

/// How many user-facing windows an app has, or that we could not tell.
public enum WindowState: Equatable, Sendable {
    case count(Int)
    /// The Accessibility API failed or timed out. Never quit on this.
    case unknown

    public var hasWindows: Bool? {
        switch self {
        case .count(let n): return n > 0
        case .unknown: return nil
        }
    }
}

public enum WindowCounting {
    /// Smaller windows are treated as helpers, not something the user looks at.
    static let minimumWidth: Double = 80
    static let minimumHeight: Double = 60
    /// Windows without a known subrole must be at least this big to count.
    static let minimumUnknownWidth: Double = 200
    static let minimumUnknownHeight: Double = 150

    static let countedSubroles: Set<String> = ["AXStandardWindow", "AXDialog"]

    public static func isUserWindow(_ w: AccessibilityWindow) -> Bool {
        guard w.role == nil || w.role == "AXWindow" else { return false }
        if let subrole = w.subrole, countedSubroles.contains(subrole) {
            // Minimized windows report their real size, which is fine.
            return w.isMinimized || (w.width >= minimumWidth && w.height >= minimumHeight)
        }
        if w.subrole == nil || w.subrole == "AXUnknown" {
            // Some Electron and Java apps leave the subrole empty for real windows.
            return w.isMinimized || (w.width >= minimumUnknownWidth && w.height >= minimumUnknownHeight)
        }
        // Floating palettes, system dialogs and the like do not keep an app alive.
        return false
    }

    public static func isUserWindow(_ w: ServerWindow) -> Bool {
        w.layer == 0 && w.alpha > 0.01 && w.width >= minimumWidth && w.height >= minimumHeight
    }

    /// Combines both sources.
    ///
    /// - Parameter accessibility: `nil` when the Accessibility call failed.
    public static func state(accessibility: [AccessibilityWindow]?, server: [ServerWindow]) -> WindowState {
        guard let accessibility else { return .unknown }
        let visibleHere = accessibility.filter(isUserWindow).count
        if visibleHere > 0 { return .count(visibleHere) }

        // Nothing on this Space. Look for windows the Accessibility API cannot
        // see: ones on another Space or in a full-screen Space.
        let elsewhere = server.filter(isUserWindow).filter { w in
            // On screen yet missing from Accessibility: trust the window server.
            if w.isOnScreen { return true }
            // Unknown values: assume the window is real.
            return (w.isOnAnySpace ?? true) && (w.isOrderedIn ?? true)
        }
        return .count(elsewhere.count)
    }
}
