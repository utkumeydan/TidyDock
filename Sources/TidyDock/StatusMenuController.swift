import AppKit
import TidyDockCore

final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store: SettingsStore
    private let session: SessionState
    private let quitLog: QuitLog
    private let updater: Updater

    var showSettings: () -> Void = {}
    var showPermissionHelp: () -> Void = {}
    var cleanableApps: () -> [NSRunningApplication] = { [] }
    var cleanUpNow: () -> Void = {}

    private var tokens: [NSObjectProtocol] = []
    private var flashTimer: Timer?
    private let recentInline = 5

    init(store: SettingsStore, session: SessionState, quitLog: QuitLog, updater: Updater) {
        self.store = store
        self.session = session
        self.quitLog = quitLog
        self.updater = updater
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        for name in [SettingsStore.didChange, SessionState.didChange] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateIcon()
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: QuitLog.didQuit, object: nil, queue: .main) { [weak self] _ in
            self?.flash()
        })
        updateIcon()
    }

    /// Opens the menu as if the icon was clicked (used for screenshots).
    func openMenu() {
        statusItem.button?.performClick(nil)
    }

    /// The menu bar icon's frame on screen, for placing notices under it.
    var anchorRect: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private var isActive: Bool {
        store.settings.isEnabled && !session.isPaused && Permissions.isTrusted
    }

    func updateIcon() {
        guard flashTimer == nil else { return }
        setIcon(isActive ? "dock.rectangle" : "pause.rectangle")
        statusItem.button?.appearsDisabled = !isActive
        statusItem.button?.toolTip = statusText
    }

    private func setIcon(_ symbol: String) {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "TidyDock")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    /// A short sparkle in the menu bar so you notice TidyDock did something.
    private func flash() {
        let frames = ["sparkle", "sparkles", "sparkle", "dock.rectangle"]
        var index = 0
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard index < frames.count else {
                timer.invalidate()
                self.flashTimer = nil
                self.updateIcon()
                return
            }
            self.setIcon(frames[index])
            index += 1
        }
    }

    private var statusText: String {
        if !Permissions.isTrusted { return L("Needs Accessibility access") }
        if !store.settings.isEnabled { return L("TidyDock is off") }
        if session.isPaused { return L("Paused until restart") }
        return L("TidyDock is on")
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = store.settings

        let header = NSMenuItem()
        header.view = MenuHeaderView(status: statusText, isActive: isActive, stats: quitLog.stats)
        menu.addItem(header)

        if !Permissions.isTrusted {
            menu.addItem(item(L("Grant Accessibility Access…"), #selector(grantAccess), symbol: "hand.raised"))
        }
        menu.addItem(.separator())

        let cleanable = cleanableApps()
        let clean = item(cleanable.isEmpty ? L("Clean Up Now") : L("Clean Up Now (%d)", cleanable.count), #selector(cleanUp), symbol: "sparkles")
        clean.isEnabled = !cleanable.isEmpty
        clean.toolTip = cleanable.compactMap(\.localizedName).joined(separator: ", ")
        if let hotkey = settings.hotkeys[.cleanNow] { clean.toolTip = [clean.toolTip ?? "", hotkey.displayString].joined(separator: "  ") }
        menu.addItem(clean)

        let enabled = item(L("Quit Apps Automatically"), #selector(toggleEnabled), symbol: "power")
        enabled.state = settings.isEnabled ? .on : .off
        menu.addItem(enabled)

        let pause = item(session.isPaused ? L("Resume") : L("Pause Until Restart"), #selector(togglePause), symbol: session.isPaused ? "play" : "pause")
        pause.isEnabled = settings.isEnabled
        menu.addItem(pause)

        if let front = NSWorkspace.shared.frontmostApplication,
           front.activationPolicy == .regular,
           let id = front.bundleIdentifier,
           id != Bundle.main.bundleIdentifier {
            let never = item(L("Never Quit “%@”", front.localizedName ?? id), #selector(toggleNeverQuit(_:)), symbol: "hand.raised")
            never.representedObject = id
            never.state = settings.isNeverQuit(bundleID: id) ? .on : .off
            menu.addItem(never)
        }

        menu.addItem(.separator())
        addRecentlyQuit(to: menu)
        menu.addItem(.separator())

        let prefs = item(L("Settings…"), #selector(openSettings), symbol: "gearshape")
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        if updater.isAvailable {
            menu.addItem(item(L("Check for Updates…"), #selector(checkForUpdates), symbol: "arrow.down.circle"))
        }
        let quit = item(L("Quit TidyDock"), #selector(quitApp), symbol: "xmark.circle")
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func addRecentlyQuit(to menu: NSMenu) {
        let header = NSMenuItem(title: L("Recently Quit"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if quitLog.entries.isEmpty {
            let empty = NSMenuItem(title: L("Nothing yet"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.indentationLevel = 1
            menu.addItem(empty)
            return
        }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        for (index, entry) in quitLog.entries.enumerated() {
            let row = recentItem(entry, index: index, relative: relative)
            if index < recentInline {
                menu.addItem(row)
            } else {
                if index == recentInline {
                    let more = NSMenuItem(title: L("More"), action: nil, keyEquivalent: "")
                    more.submenu = NSMenu()
                    menu.addItem(more)
                }
                menu.items.last?.submenu?.addItem(row)
            }
        }
    }

    private func recentItem(_ entry: QuitEntry, index: Int, relative: RelativeDateTimeFormatter) -> NSMenuItem {
        var detail = relative.localizedString(for: entry.date, relativeTo: Date())
        if entry.bytes > 0 { detail += " · " + Format.bytes(entry.bytes) }
        let title = NSMutableAttributedString(string: entry.name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        title.append(NSAttributedString(string: "   " + detail, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let row = NSMenuItem(title: entry.name, action: nil, keyEquivalent: "")
        row.attributedTitle = title
        row.image = AppInfo(bundleID: entry.bundleID).icon

        let actions = NSMenu()
        let reopen = item(L("Reopen"), #selector(reopen(_:)), symbol: "arrow.uturn.backward")
        reopen.tag = index
        reopen.isEnabled = entry.bundleURL != nil
        actions.addItem(reopen)
        let never = item(L("Never Quit This App"), #selector(toggleNeverQuit(_:)), symbol: "hand.raised")
        never.representedObject = entry.bundleID
        never.state = store.settings.isNeverQuit(bundleID: entry.bundleID) ? .on : .off
        actions.addItem(never)
        row.submenu = actions
        return row
    }

    private func item(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    // MARK: - Actions

    @objc private func toggleEnabled() { store.update { $0.isEnabled.toggle() } }
    @objc private func togglePause() { session.isPaused.toggle() }
    @objc private func openSettings() { showSettings() }
    @objc private func grantAccess() { showPermissionHelp() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func cleanUp() { cleanUpNow() }

    @objc private func toggleNeverQuit(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.update { $0.toggleNeverQuit(bundleID: id) }
    }

    @objc private func reopen(_ sender: NSMenuItem) {
        guard quitLog.entries.indices.contains(sender.tag), let url = quitLog.entries[sender.tag].bundleURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// The card at the top of the menu: status plus today's, this week's and all-time numbers.
private final class MenuHeaderView: NSView {
    init(status: String, isActive: Bool, stats: UsageStats) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 96))
        let now = Date()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let title = UI.title(status, size: 13, weight: .semibold)
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = (isActive ? NSColor.systemGreen : NSColor.systemOrange).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
        let today = stats.today(now: now)
        let subtitle = UI.title(today.quits == 0 ? L("Nothing quit today") : L("Today: %@", Format.summary(today)), size: 11)
        subtitle.textColor = .secondaryLabelColor
        let heading = UI.hstack([icon, UI.vstack([UI.hstack([dot, title], spacing: 6), subtitle], spacing: 2)], spacing: 10)

        let week = stats.lastSevenDays(now: now)
        let figures = UI.hstack([
            figure(L("This week"), Format.summary(week)),
            figure(L("All time"), Format.summary(stats.allTime)),
        ], spacing: 18)

        let stack = UI.vstack([heading, figures], spacing: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func figure(_ label: String, _ value: String) -> NSView {
        let caption = UI.title(label.uppercased(), size: 9, weight: .semibold)
        caption.textColor = .tertiaryLabelColor
        let number = UI.title(value, size: 12, weight: .medium)
        return UI.vstack([caption, number], spacing: 1)
    }
}
