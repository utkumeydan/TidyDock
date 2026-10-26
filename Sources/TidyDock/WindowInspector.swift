import AppKit
import ApplicationServices
import TidyDockCore

/// Reads an app's windows from the Accessibility API and the window server.
enum WindowInspector {
    /// Keeps a hung app from blocking TidyDock for the default six seconds.
    private static let messagingTimeout: Float = 0.5

    static func applicationElement(for pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    /// The app's window elements on the current Space, or `nil` when the app did not answer.
    static func windowElements(for pid: pid_t) -> [AXUIElement]? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(applicationElement(for: pid), kAXWindowsAttribute as CFString, &value)
        switch error {
        case .success:
            return value as? [AXUIElement] ?? []
        case .noValue, .attributeUnsupported:
            // The app answered and has no window list.
            return []
        default:
            return nil
        }
    }

    static func describe(_ element: AXUIElement) -> AccessibilityWindow {
        let size = sizeAttribute(element)
        return AccessibilityWindow(
            role: stringAttribute(element, kAXRoleAttribute),
            subrole: stringAttribute(element, kAXSubroleAttribute),
            isMinimized: boolAttribute(element, kAXMinimizedAttribute),
            width: Double(size.width),
            height: Double(size.height)
        )
    }

    /// All windows on every Space, grouped by owning process.
    static func serverWindowsByPID() -> [pid_t: [ServerWindow]] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        let spaces = SpaceLookup.shared
        var result: [pid_t: [ServerWindow]] = [:]
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
            let windowID = info[kCGWindowNumber as String] as? CGWindowID
            result[pid, default: []].append(ServerWindow(
                layer: layer,
                alpha: info[kCGWindowAlpha as String] as? Double ?? 1,
                width: Double(bounds.width),
                height: Double(bounds.height),
                isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                isOnAnySpace: windowID.flatMap { spaces.isOnAnySpace(windowID: $0) },
                isOrderedIn: windowID.flatMap { spaces.isOrderedIn(windowID: $0) }
            ))
        }
        return result
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ name: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func sizeAttribute(_ element: AXUIElement) -> CGSize {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return .zero }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }
}

/// Asks the window server which Spaces a window is on.
///
/// This uses a private CoreGraphics function, looked up at runtime so that
/// TidyDock keeps working (more cautiously) if Apple removes it.
final class SpaceLookup {
    static let shared = SpaceLookup()

    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias IsOrderedInFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<DarwinBoolean>) -> Int32

    private let connection: Int32?
    private let copySpaces: CopySpacesFn?
    private let isOrderedInFn: IsOrderedInFn?

    /// Ask about every kind of Space (current, other and full-screen).
    private let allSpacesMask: Int32 = 0x7

    private init() {
        let handle = dlopen(nil, RTLD_NOW)
        let main = Self.symbol(handle, ["CGSMainConnectionID", "SLSMainConnectionID"]).map { unsafeBitCast($0, to: MainConnectionFn.self) }
        copySpaces = Self.symbol(handle, ["CGSCopySpacesForWindows", "SLSCopySpacesForWindows"]).map { unsafeBitCast($0, to: CopySpacesFn.self) }
        isOrderedInFn = Self.symbol(handle, ["SLSWindowIsOrderedIn", "CGSWindowIsOrderedIn"]).map { unsafeBitCast($0, to: IsOrderedInFn.self) }
        connection = main?()
    }

    var isAvailable: Bool { connection != nil && copySpaces != nil }

    func isOnAnySpace(windowID: CGWindowID) -> Bool? {
        guard let connection, let copySpaces else { return nil }
        let ids = [NSNumber(value: windowID)] as CFArray
        guard let spaces = copySpaces(connection, allSpacesMask, ids)?.takeRetainedValue() else { return nil }
        return CFArrayGetCount(spaces) > 0
    }

    func isOrderedIn(windowID: CGWindowID) -> Bool? {
        guard let connection, let isOrderedInFn else { return nil }
        var value: DarwinBoolean = false
        guard isOrderedInFn(connection, windowID, &value) == 0 else { return nil }
        return value.boolValue
    }

    private static func symbol(_ handle: UnsafeMutableRawPointer?, _ names: [String]) -> UnsafeMutableRawPointer? {
        for name in names {
            if let pointer = dlsym(handle, name) { return pointer }
        }
        return nil
    }
}
