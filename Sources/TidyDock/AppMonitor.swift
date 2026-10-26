import AppKit
import ApplicationServices
import TidyDockCore

/// Tracks running Dock apps, watches their windows and quits the ones the policy says to.
final class AppMonitor {
    /// Posted with `bundleIDKey` when the user keeps reopening an app TidyDock quit.
    static let shouldSuggestNeverQuit = Notification.Name("TidyDockShouldSuggestNeverQuit")
    static let bundleIDKey = "bundleID"

    private let settingsStore: SettingsStore
    private let session: SessionState
    private let quitLog: QuitLog

    private var records: [pid_t: AppRecord] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    private var pendingRefresh: Set<pid_t> = []
    /// Apps we asked to quit, recorded only once they actually terminate
    /// (the user may cancel a "save changes?" dialog).
    private var awaitingTermination: [pid_t: QuitEntry] = [:]
    /// Apps that quit close together are reported as one batch.
    private var terminatedBatch: [QuitEntry] = []
    private var batchTimer: Timer?
    private var frontmostPID: pid_t?

    private var pollTimer: Timer?
    private var recheckTimer: Timer?
    private var workspaceTokens: [NSObjectProtocol] = []

    /// Fallback for window changes the Accessibility notifications miss.
    private let pollInterval: TimeInterval = 3
    /// Lets an app finish replacing a window (closing a tab, switching documents) before we look.
    private let eventDebounce: TimeInterval = 0.25

    private let ownBundleID = Bundle.main.bundleIdentifier

    init(settingsStore: SettingsStore, session: SessionState, quitLog: QuitLog) {
        self.settingsStore = settingsStore
        self.session = session
        self.quitLog = quitLog
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ handler: @escaping (NSRunningApplication) -> Void) {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    handler(app)
                }
            })
        }
        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] in
            self?.track($0)
            self?.noticeRelaunch($0)
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] in self?.untrack($0.processIdentifier) }
        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.activated($0) }
        observe(NSWorkspace.didHideApplicationNotification) { [weak self] in self?.scheduleRefresh($0.processIdentifier) }
        observe(NSWorkspace.didUnhideApplicationNotification) { [weak self] in self?.scheduleRefresh($0.processIdentifier) }

        for name in [SettingsStore.didChange, SessionState.didChange] {
            workspaceTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.evaluateAll()
            })
        }

        frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        NSWorkspace.shared.runningApplications.forEach(track)

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
        pollTimer?.tolerance = 0.5
        refreshAll()
    }

    /// Call when Accessibility access is granted after launch.
    func accessibilityAccessChanged() {
        for pid in records.keys where observers[pid] == nil {
            attachObserver(pid)
        }
        refreshAll()
    }

    // MARK: - Tracking

    private func track(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard records[pid] == nil, !app.isTerminated, app.bundleIdentifier != ownBundleID else { return }
        records[pid] = AppRecord(
            pid: pid,
            bundleID: app.bundleIdentifier,
            isRegularApp: app.activationPolicy == .regular,
            isHidden: app.isHidden,
            isFrontmost: pid == frontmostPID,
            now: Date()
        )
        if app.activationPolicy == .regular { attachObserver(pid) }
        scheduleRefresh(pid)
    }

    private func noticeRelaunch(_ app: NSRunningApplication) {
        guard settingsStore.settings.smartSuggestions,
              let id = app.bundleIdentifier,
              settingsStore.settings.isEligible(bundleID: id),
              quitLog.appLaunched(bundleID: id, now: Date())
        else { return }
        NotificationCenter.default.post(name: Self.shouldSuggestNeverQuit, object: self, userInfo: [Self.bundleIDKey: id])
    }

    private func untrack(_ pid: pid_t) {
        if let entry = awaitingTermination.removeValue(forKey: pid) {
            terminatedBatch.append(entry)
            batchTimer?.invalidate()
            batchTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.quitLog.record(self.terminatedBatch)
                self.terminatedBatch = []
            }
        }
        records[pid] = nil
        pendingRefresh.remove(pid)
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    private func activated(_ app: NSRunningApplication) {
        let now = Date()
        // The app that was in front was in use until this moment.
        if let previous = frontmostPID {
            records[previous]?.markActive(now: now)
            records[previous]?.isFrontmost = false
        }
        frontmostPID = app.processIdentifier
        records[app.processIdentifier]?.markActive(now: now)
        records[app.processIdentifier]?.isFrontmost = true
        evaluateAll()
    }

    // MARK: - Accessibility notifications

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private func attachObserver(_ pid: pid_t) {
        guard observers[pid] == nil, AXIsProcessTrusted() else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { observer, element, _, refcon in
            guard let refcon else { return }
            let monitor = Unmanaged<AppMonitor>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) != .success {
                // Fall back to the app this observer was created for.
                guard let owner = monitor.observers.first(where: { $0.value === observer })?.key else { return }
                pid = owner
            }
            monitor.scheduleRefresh(pid)
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = WindowInspector.applicationElement(for: pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    /// Window destroyed notifications only arrive for windows we subscribed to.
    private func watchWindows(_ elements: [AXUIElement], pid: pid_t) {
        guard let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for element in elements {
            // Returns "already registered" for windows we know, which is fine.
            AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
        }
    }

    // MARK: - Refreshing

    private func scheduleRefresh(_ pid: pid_t) {
        guard records[pid] != nil, pendingRefresh.insert(pid).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + eventDebounce) { [weak self] in
            guard let self, self.pendingRefresh.remove(pid) != nil else { return }
            self.refresh([pid])
        }
    }

    private func refreshAll() {
        refresh(Array(records.keys))
    }

    private func refresh(_ pids: [pid_t]) {
        let now = Date()
        let serverWindows = WindowInspector.serverWindowsByPID()
        for pid in pids {
            guard var record = records[pid], let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
                untrack(pid)
                continue
            }
            record.isRegularApp = app.activationPolicy == .regular
            record.isHidden = app.isHidden
            guard record.isRegularApp else {
                records[pid] = record
                continue
            }
            if observers[pid] == nil { attachObserver(pid) }

            let elements = AXIsProcessTrusted() ? WindowInspector.windowElements(for: pid) : nil
            if let elements { watchWindows(elements, pid: pid) }
            let state = WindowCounting.state(
                accessibility: elements?.map(WindowInspector.describe),
                server: serverWindows[pid] ?? []
            )
            if state != record.windowState {
                log.info("\(record.bundleID ?? "?", privacy: .public) windows: \(String(describing: state), privacy: .public)")
            }
            record.update(windowState: state, now: now)
            // A window came back, so the quit was cancelled.
            if record.quitRequestedAt == nil { awaitingTermination[pid] = nil }
            records[pid] = record
        }
        evaluateAll()
    }

    // MARK: - Deciding

    private func evaluateAll() {
        let now = Date()
        let context = PolicyContext(ownBundleID: ownBundleID, isSessionPaused: session.isPaused)
        let settings = settingsStore.settings
        var earliest: Date?

        for (pid, record) in records {
            switch QuitPolicy.decide(record, settings: settings, context: context, now: now) {
            case .keep:
                break
            case .recheck(let date):
                earliest = earliest.map { min($0, date) } ?? date
            case .quit(let reason):
                quit(pid, reason: reason, now: now)
            }
        }

        recheckTimer?.invalidate()
        if let earliest {
            // A short floor keeps a deadline that is due right now from spinning.
            let delay = max(earliest.timeIntervalSinceNow, 0.05)
            recheckTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.refreshAll()
            }
        }
    }

    // MARK: - Clean up now

    /// Running Dock apps without windows that "Clean Up Now" would quit.
    func cleanableApps() -> [NSRunningApplication] {
        let context = PolicyContext(ownBundleID: ownBundleID, isSessionPaused: false)
        return records.values
            .filter { QuitPolicy.isCleanable($0, settings: settingsStore.settings, context: context) }
            .compactMap { NSRunningApplication(processIdentifier: $0.pid) }
    }

    func cleanUpNow() {
        let now = Date()
        for app in cleanableApps() {
            quit(app.processIdentifier, reason: .cleanUp, now: now)
        }
    }

    private func quit(_ pid: pid_t, reason: QuitReason, now: Date) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        records[pid]?.markQuitRequested(now: now)
        // Measure first: the memory is gone once the app quits.
        let bytes = MemoryProbe.footprint(of: pid)
        // A normal quit, like ⌘Q: the app can still ask to save documents.
        guard app.terminate() else {
            log.notice("\(app.bundleIdentifier ?? "?", privacy: .public) refused to quit")
            return
        }
        awaitingTermination[pid] = QuitEntry(
            bundleID: app.bundleIdentifier ?? "",
            name: app.localizedName ?? app.bundleIdentifier ?? "?",
            bundleURL: app.bundleURL,
            reason: reason,
            date: now,
            bytes: bytes
        )
    }
}
