import Testing
@testable import TidyDockCore

private func ax(_ subrole: String?, minimized: Bool = false, _ width: Double = 800, _ height: Double = 600) -> AccessibilityWindow {
    AccessibilityWindow(role: "AXWindow", subrole: subrole, isMinimized: minimized, width: width, height: height)
}

private func server(onScreen: Bool, onSpace: Bool?, orderedIn: Bool? = true, _ width: Double = 800, _ height: Double = 600, alpha: Double = 1) -> ServerWindow {
    ServerWindow(layer: 0, alpha: alpha, width: width, height: height, isOnScreen: onScreen, isOnAnySpace: onSpace, isOrderedIn: orderedIn)
}

@Suite struct WindowCountingTests {
    @Test func countsStandardWindowsAndDialogs() {
        #expect(WindowCounting.state(accessibility: [ax("AXStandardWindow"), ax("AXDialog", 400, 200)], server: []) == .count(2))
    }

    @Test func countsMinimizedWindows() {
        #expect(WindowCounting.state(accessibility: [ax("AXStandardWindow", minimized: true, 0, 0)], server: []) == .count(1))
    }

    @Test func ignoresFloatingPalettesAndTinyHelpers() {
        let windows = [ax("AXFloatingWindow"), ax("AXSystemDialog"), ax("AXStandardWindow", 1, 1), ax(nil, 120, 100)]
        #expect(WindowCounting.state(accessibility: windows, server: []) == .count(0))
    }

    @Test func countsLargeWindowsWithoutASubrole() {
        #expect(WindowCounting.state(accessibility: [ax("AXUnknown"), ax(nil)], server: []) == .count(2))
    }

    @Test func failedAccessibilityCallIsUnknown() {
        #expect(WindowCounting.state(accessibility: nil, server: [server(onScreen: true, onSpace: true)]) == .unknown)
    }

    @Test func findsWindowsOnOtherSpaces() {
        // Accessibility only sees the current Space.
        #expect(WindowCounting.state(accessibility: [], server: [server(onScreen: false, onSpace: true)]) == .count(1))
    }

    @Test func ignoresOrderedOutWindows() {
        // Discord-style apps hide their window instead of closing it.
        #expect(WindowCounting.state(accessibility: [], server: [server(onScreen: false, onSpace: false)]) == .count(0))
    }

    @Test func ignoresClosedWindowsAppsKeepAround() {
        // Excel keeps its closed workbook window on a Space, but ordered out.
        #expect(WindowCounting.state(accessibility: [], server: [server(onScreen: false, onSpace: true, orderedIn: false)]) == .count(0))
    }

    @Test func assumesWindowsAreRealWhenSpacesAreUnknown() {
        #expect(WindowCounting.state(accessibility: [], server: [server(onScreen: false, onSpace: nil)]) == .count(1))
        #expect(WindowCounting.state(accessibility: [], server: [server(onScreen: false, onSpace: true, orderedIn: nil)]) == .count(1))
    }

    @Test func ignoresTransparentAndTinyServerWindows() {
        let windows = [server(onScreen: true, onSpace: true, alpha: 0), server(onScreen: true, onSpace: true, 10, 10)]
        #expect(WindowCounting.state(accessibility: [], server: windows) == .count(0))
    }
}
