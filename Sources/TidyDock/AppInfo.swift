import AppKit

/// Display name and icon for a bundle ID, whether or not the app is running.
struct AppInfo {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let url: URL?

    init(bundleID: String) {
        self.bundleID = bundleID
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        self.url = url
        if let name = running?.localizedName {
            self.name = name
        } else if let url {
            self.name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        } else {
            self.name = bundleID
        }
        let icon = running?.icon ?? url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        icon?.size = NSSize(width: 16, height: 16)
        self.icon = icon
    }

    /// Running Dock apps, sorted by name, without TidyDock itself.
    static func runningRegularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }
}
