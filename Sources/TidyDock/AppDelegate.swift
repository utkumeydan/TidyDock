import AppKit
import TidyDockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Screenshot mode keeps its sample data away from the user's real settings.
    private let store = SettingsStore(defaults: ScreenshotMode.defaults ?? .standard)
    private let session = SessionState()
    private let quitLog = QuitLog(defaults: ScreenshotMode.defaults ?? .standard)
    private let hotkeys = HotkeyManager()
    private var updater: Updater!
    private var monitor: AppMonitor!
    private var menu: StatusMenuController!
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var settingsToken: NSObjectProtocol?
    private var accessTimer: Timer?
    private let notice = NoticePanel()
    private var noticeTokens: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        updater = Updater()
        monitor = AppMonitor(settingsStore: store, session: session, quitLog: quitLog)
        menu = StatusMenuController(store: store, session: session, quitLog: quitLog, updater: updater)
        menu.showSettings = { [weak self] in self?.showSettings() }
        menu.showPermissionHelp = { [weak self] in self?.showOnboarding(at: .permission) }
        menu.cleanableApps = { [weak self] in self?.monitor.cleanableApps() ?? [] }
        menu.cleanUpNow = { [weak self] in self?.monitor.cleanUpNow() }
        notice.anchor = { [weak self] in self?.menu.anchorRect }
        noticeTokens.append(NotificationCenter.default.addObserver(forName: QuitLog.didQuit, object: nil, queue: .main) { [weak self] note in
            guard let entries = note.userInfo?[QuitLog.entriesKey] as? [QuitEntry] else { return }
            self?.showQuitNotice(entries)
        })
        noticeTokens.append(NotificationCenter.default.addObserver(forName: AppMonitor.shouldSuggestNeverQuit, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?[AppMonitor.bundleIDKey] as? String else { return }
            self?.suggestNeverQuit(id)
        })

        hotkeys.handler = { [weak self] action in self?.perform(action) }
        hotkeys.apply(store.settings.hotkeys)
        settingsToken = NotificationCenter.default.addObserver(forName: SettingsStore.didChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.hotkeys.apply(self.store.settings.hotkeys)
        }

        if let scene = ScreenshotMode.scene {
            // Never watch or quit real apps while taking screenshots.
            showScreenshot(scene)
            return
        }

        monitor.start()
        if !OnboardingWindowController.hasCompleted {
            showOnboarding(at: .welcome)
        } else if !Permissions.isTrusted {
            // Usually after an update: macOS forgot the permission.
            showOnboarding(at: .permission)
        }
        watchForAccess()
    }

    /// Opening TidyDock again from Finder or Spotlight shows the settings,
    /// since a menu bar app has no window of its own.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func showSettings(tab: Int? = nil) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(store: store, session: session, quitLog: quitLog, updater: updater) { [weak self] in
                self?.showOnboarding(at: Permissions.isTrusted ? .welcome : .permission)
            }
        }
        if let tab { settingsWindow?.selectTab(tab) }
        settingsWindow?.show()
    }

    private func showOnboarding(at page: OnboardingWindowController.Page, watch: Bool = true) {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController(store: store, onAccessGranted: { [weak self] in
                self?.accessGranted()
            }, onFinish: { [weak self] in
                self?.onboardingWindow = nil
            })
        }
        onboardingWindow?.show(at: page, watchAccess: watch)
    }

    /// Notices the permission even when the walkthrough was closed early.
    private func watchForAccess() {
        guard !Permissions.isTrusted else { return }
        accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard Permissions.isTrusted else { return }
            self?.accessGranted()
        }
    }

    private func accessGranted() {
        accessTimer?.invalidate()
        accessTimer = nil
        monitor.accessibilityAccessChanged()
        menu.updateIcon()
        NotificationCenter.default.post(name: SessionState.didChange, object: nil)
    }

    // MARK: - Notices

    private func showQuitNotice(_ entries: [QuitEntry]) {
        guard store.settings.showUndoNotice, let first = entries.first else { return }
        let bytes = entries.reduce(0) { $0 + $1.bytes }
        let freed = bytes > 0 ? L("%@ freed", Format.bytes(bytes)) : nil
        let title: String
        var detail: String?
        if entries.count == 1 {
            title = L("Quit %@", first.name)
            let reason: String
            switch first.reason {
            case .noWindows: reason = L("No windows were open")
            case .idle: reason = L("Not used for a while")
            case .cleanUp: reason = L("Cleaned up")
            }
            detail = [reason, freed].compactMap { $0 }.joined(separator: " · ")
        } else {
            title = L("Quit %d apps", entries.count)
            detail = [entries.map(\.name).joined(separator: ", "), freed].compactMap { $0 }.joined(separator: " · ")
        }
        let icon = entries.count == 1 ? AppInfo(bundleID: first.bundleID).icon.map(Self.large) : nil
        notice.show(icon: icon, title: title, detail: detail, actions: [
            .init(title: L("Undo"), isPrimary: false) {
                for url in entries.compactMap(\.bundleURL) {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
            },
        ], duration: 5)
    }

    private func suggestNeverQuit(_ bundleID: String, name: String? = nil) {
        quitLog.markSuggested(bundleID: bundleID)
        let info = AppInfo(bundleID: bundleID)
        notice.show(icon: info.icon.map(Self.large), title: L("You keep reopening %@", name ?? info.name),
                    detail: L("Stop quitting it automatically?"), actions: [
            .init(title: L("Never Quit"), isPrimary: true) { [weak self] in
                self?.store.update { settings in
                    if !settings.isNeverQuit(bundleID: bundleID) { settings.toggleNeverQuit(bundleID: bundleID) }
                }
            },
            .init(title: L("Keep Quitting"), isPrimary: false) {},
        ], duration: 15)
    }

    private static func large(_ icon: NSImage) -> NSImage {
        let copy = icon.copy() as! NSImage
        copy.size = NSSize(width: 32, height: 32)
        return copy
    }

    private func showScreenshot(_ scene: ScreenshotMode.Scene) {
        ScreenshotMode.loadSampleData(into: quitLog)
        switch scene {
        case .welcome: showOnboarding(at: .welcome, watch: false)
        case .permission: showOnboarding(at: .permission, watch: false)
        case .setup: showOnboarding(at: .setup, watch: false)
        case .general, .apps, .shortcuts, .about:
            showSettings(tab: scene.settingsTab)
        case .notice:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showQuitNotice([ScreenshotMode.sampleEntry])
            }
        case .suggestion:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.suggestNeverQuit("com.spotify.client", name: "Spotify")
            }
        case .menu:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.menu.openMenu()
            }
        }
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .cleanNow:
            monitor.cleanUpNow()
        case .toggleSessionPause:
            session.isPaused.toggle()
        case .toggleExcludeFrontmostApp:
            guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
            store.update { $0.toggleNeverQuit(bundleID: id) }
            NSSound(named: "Tink")?.play()
        }
    }
}
