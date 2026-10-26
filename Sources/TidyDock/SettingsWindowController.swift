import AppKit
import UniformTypeIdentifiers
import TidyDockCore

final class SettingsWindowController: NSWindowController {
    private let tabs: NSTabViewController

    init(store: SettingsStore, session: SessionState, quitLog: QuitLog, updater: Updater, showOnboarding: @escaping () -> Void) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        // Otherwise the window takes the (empty) title of the selected pane.
        tabs.canPropagateSelectedChildViewControllerTitle = false
        func add(_ controller: NSViewController, _ title: String, _ symbol: String) {
            let item = NSTabViewItem(viewController: controller)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add(GeneralPane(store: store, session: session, quitLog: quitLog, showOnboarding: showOnboarding), L("General"), "gearshape")
        add(AppsPane(store: store), L("Apps"), "square.grid.2x2")
        add(ShortcutsPane(store: store), L("Shortcuts"), "command")
        add(AboutPane(updater: updater), L("About"), "info.circle")

        self.tabs = tabs
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = L("TidyDock Settings")
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func selectTab(_ index: Int) {
        tabs.selectedTabViewItemIndex = index
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Preset values shared by Settings and the setup page of the walkthrough.
enum Choices {
    static let delays: [TimeInterval] = [0, 0.5, 1, 2, 3, 5, 10]
    static let idleMinutes = [15, 30, 60, 120, 240, 480, 1440]

    static func delayPopup(selected: TimeInterval, target: AnyObject, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton()
        for (index, value) in delays.enumerated() {
            popup.addItem(withTitle: value == 0 ? L("Immediately") : (value == 1 ? L("1 second") : L("%@ seconds", value.formatted())))
            popup.lastItem?.tag = index
        }
        selectDelay(selected, in: popup)
        popup.target = target
        popup.action = action
        return popup
    }

    static func selectDelay(_ value: TimeInterval, in popup: NSPopUpButton) {
        let index = delays.enumerated().min { abs($0.element - value) < abs($1.element - value) }?.offset ?? 2
        popup.selectItem(withTag: index)
    }

    static func delay(from popup: NSPopUpButton) -> TimeInterval {
        delays[max(0, min(popup.selectedTag(), delays.count - 1))]
    }

    static func idlePopup(selected: Int, target: AnyObject, action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton()
        for minutes in idleMinutes {
            popup.addItem(withTitle: describe(minutes: minutes))
            popup.lastItem?.tag = minutes
        }
        selectIdle(selected, in: popup)
        popup.target = target
        popup.action = action
        return popup
    }

    static func selectIdle(_ minutes: Int, in popup: NSPopUpButton) {
        let closest = idleMinutes.min { abs($0 - minutes) < abs($1 - minutes) } ?? 120
        popup.selectItem(withTag: closest)
    }

    static func describe(minutes: Int) -> String {
        if minutes < 60 { return L("%d minutes", minutes) }
        if minutes == 60 { return L("1 hour") }
        return L("%d hours", minutes / 60)
    }
}

// MARK: - Shared pane plumbing

private class Pane: NSViewController {
    let width: CGFloat = 560

    private var tokens: [NSObjectProtocol] = []

    /// Lays out sections top to bottom with the standard margins.
    func makeView(_ sections: [NSView]) -> NSView {
        let stack = UI.vstack(sections, spacing: 20)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        UI.fillWidth(stack)
        return stack
    }

    func observe(_ names: [Notification.Name]) {
        for name in names {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
            })
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    func reload() {}

    /// Wraps a view with padding so it can sit inside a card.
    func padded(_ view: NSView, _ inset: CGFloat = 14) -> NSView {
        let wrapper = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -inset),
        ])
        return wrapper
    }

    /// Indents a label to line up with card content.
    func indent(_ view: NSView) -> NSView {
        let wrapper = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            view.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }
}

// MARK: - General

private final class GeneralPane: Pane {
    private let store: SettingsStore
    private let session: SessionState
    private let quitLog: QuitLog
    private let showOnboarding: () -> Void

    private let statusTitle = UI.title("", size: 15, weight: .semibold)
    private let statusDetail = UI.title("", size: 12)
    private var enabledSwitch: NSSwitch!
    private var grantButton: NSButton!
    private var delayPopup: NSPopUpButton!
    private var idleSwitch: NSSwitch!
    private var idlePopup: NSPopUpButton!
    private var loginSwitch: NSSwitch!
    private var noticeSwitch: NSSwitch!
    private var suggestSwitch: NSSwitch!
    private let weekValue = UI.title("", size: 17, weight: .semibold)
    private let totalValue = UI.title("", size: 17, weight: .semibold)
    private let memoryValue = UI.title("", size: 17, weight: .semibold)

    init(store: SettingsStore, session: SessionState, quitLog: QuitLog, showOnboarding: @escaping () -> Void) {
        self.store = store
        self.session = session
        self.quitLog = quitLog
        self.showOnboarding = showOnboarding
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let s = store.settings
        enabledSwitch = UI.switchControl(s.isEnabled, target: self, action: #selector(enabledChanged))
        enabledSwitch.controlSize = .regular
        grantButton = UI.button(L("Grant Access…"), target: self, action: #selector(openOnboarding), primary: true)

        delayPopup = Choices.delayPopup(selected: s.quitDelay, target: self, action: #selector(delayChanged))
        idleSwitch = UI.switchControl(s.idleQuitEnabled, target: self, action: #selector(idleChanged))
        idlePopup = Choices.idlePopup(selected: s.idleMinutes, target: self, action: #selector(idleChanged))
        loginSwitch = UI.switchControl(LaunchAtLogin.isEnabled, target: self, action: #selector(loginChanged))
        noticeSwitch = UI.switchControl(s.showUndoNotice, target: self, action: #selector(noticesChanged))
        suggestSwitch = UI.switchControl(s.smartSuggestions, target: self, action: #selector(noticesChanged))

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let statusText = UI.vstack([statusTitle, statusDetail], spacing: 3)
        statusText.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let statusRow = UI.hstack([icon, statusText, spacer, grantButton, enabledSwitch], spacing: 12)
        let figures = UI.hstack([
            figure(weekValue, L("Apps quit this week")),
            figure(memoryValue, L("Memory freed this week")),
            figure(totalValue, L("Apps quit in total")),
        ], spacing: 0)
        figures.distribution = .fillEqually
        figures.alignment = .top
        let statusCard = FormSection(rows: [padded(statusRow), padded(figures, 12)])

        let quitting = FormSection(title: L("Quitting"), rows: [
            FormRow(icon: IconTile(symbol: "timer", color: .systemBlue), title: L("Quit delay"),
                    subtitle: L("How long to wait after an app's last window closes."), accessory: delayPopup),
            FormRow(icon: IconTile(symbol: "moon.zzz.fill", color: .systemIndigo), title: L("Quit idle apps"),
                    subtitle: L("Also quit apps you haven't brought to the front for a while. The front app is never quit."), accessory: idleSwitch),
            FormRow(icon: IconTile(symbol: "hourglass", color: .systemPurple), title: L("Idle after"), accessory: idlePopup),
        ])

        let feedback = FormSection(title: L("Notices"), rows: [
            FormRow(icon: IconTile(symbol: "arrow.uturn.backward", color: .systemTeal), title: L("Undo notice"),
                    subtitle: L("Shows what was quit under the menu bar icon, with an Undo button."), accessory: noticeSwitch),
            FormRow(icon: IconTile(symbol: "lightbulb.fill", color: .systemYellow), title: L("Smart suggestions"),
                    subtitle: L("If you keep reopening an app right after it's quit, offers to stop quitting it."), accessory: suggestSwitch),
        ])

        let system = FormSection(title: L("System"), rows: [
            FormRow(icon: IconTile(symbol: "power", color: .systemGreen), title: L("Open at login"), accessory: loginSwitch),
            FormRow(icon: IconTile(symbol: "sparkles", color: .systemPink), title: L("Welcome tour"),
                    subtitle: L("See the introduction and permission steps again."),
                    accessory: UI.button(L("Show"), target: self, action: #selector(openOnboarding))),
        ])

        view = makeView([statusCard, quitting, feedback, system])
        observe([SettingsStore.didChange, SessionState.didChange, QuitLog.didChange])
    }

    private func figure(_ value: NSTextField, _ caption: String) -> NSView {
        // Long captions (German, French…) wrap within their third of the card.
        let label = UI.wrapping(caption, size: 11, width: 150, alignment: .center)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        return UI.vstack([value, label], spacing: 2, alignment: .centerX)
    }

    override func reload() {
        let s = store.settings
        let trusted = Permissions.isTrusted
        let stats = quitLog.stats
        let week = stats.lastSevenDays(now: Date())
        weekValue.stringValue = "\(week.quits)"
        memoryValue.stringValue = Format.bytes(week.bytes)
        totalValue.stringValue = "\(stats.allTime.quits)"
        noticeSwitch.state = s.showUndoNotice ? .on : .off
        suggestSwitch.state = s.smartSuggestions ? .on : .off

        if !trusted {
            statusTitle.stringValue = L("Needs Accessibility access")
            statusTitle.textColor = .systemOrange
        } else if !s.isEnabled {
            statusTitle.stringValue = L("TidyDock is off")
            statusTitle.textColor = .secondaryLabelColor
        } else if session.isPaused {
            statusTitle.stringValue = L("Paused until restart")
            statusTitle.textColor = .systemOrange
        } else {
            statusTitle.stringValue = L("TidyDock is on")
            statusTitle.textColor = .labelColor
        }
        statusDetail.stringValue = !trusted
            ? L("TidyDock can't see windows until you allow access.")
            : stats.allTime.quits == 0
            ? L("Close an app's last window to see it in action.")
            : L("%@ freed so far", Format.bytes(stats.allTime.bytes))
        statusDetail.textColor = .secondaryLabelColor
        grantButton.isHidden = trusted
        enabledSwitch.isHidden = !trusted
        enabledSwitch.state = s.isEnabled ? .on : .off

        Choices.selectDelay(s.quitDelay, in: delayPopup)
        idleSwitch.state = s.idleQuitEnabled ? .on : .off
        idlePopup.isEnabled = s.idleQuitEnabled
        Choices.selectIdle(s.idleMinutes, in: idlePopup)
        loginSwitch.state = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval ? .on : .off
    }

    @objc private func enabledChanged() { store.update { $0.isEnabled = enabledSwitch.state == .on } }
    @objc private func delayChanged() { store.update { $0.quitDelay = Choices.delay(from: delayPopup) } }

    @objc private func idleChanged() {
        store.update {
            $0.idleQuitEnabled = idleSwitch.state == .on
            $0.idleMinutes = idlePopup.selectedTag()
        }
    }

    @objc private func loginChanged() {
        LaunchAtLogin.set(loginSwitch.state == .on)
        if LaunchAtLogin.needsApproval {
            let alert = NSAlert()
            alert.messageText = L("Approve TidyDock in System Settings")
            alert.informativeText = L("Approve TidyDock under System Settings › General › Login Items.")
            alert.runModal()
        }
        reload()
    }

    @objc private func openOnboarding() { showOnboarding() }

    @objc private func noticesChanged() {
        store.update {
            $0.showUndoNotice = noticeSwitch.state == .on
            $0.smartSuggestions = suggestSwitch.state == .on
        }
    }
}

// MARK: - Apps

private final class AppsPane: Pane, NSTableViewDataSource, NSTableViewDelegate {
    private let store: SettingsStore
    private let modePopup = NSPopUpButton()
    private let listHeader = UI.title("", size: 13, weight: .semibold)
    private let listFooter = UI.wrapping("", width: 480)
    private let emptyLabel = UI.title("", size: 12)
    private let table = NSTableView()
    private let addButton = NSButton()
    private let removeButton = NSButton()

    private var items: [AppInfo] = []

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var listKeyPath: WritableKeyPath<TidySettings, [String]> {
        store.settings.mode == .allExceptExcluded ? \.excludedBundleIDs : \.includedBundleIDs
    }

    override func loadView() {
        modePopup.addItem(withTitle: L("All apps, except the list below"))
        modePopup.addItem(withTitle: L("Only the apps in the list below"))
        modePopup.target = self
        modePopup.action = #selector(modeChanged)

        let mode = FormSection(title: L("Which apps should TidyDock quit?"), rows: [
            FormRow(icon: IconTile(symbol: "square.stack.3d.up.fill", color: .systemBlue), title: L("Apply to"), accessory: modePopup),
        ])

        table.addTableColumn(NSTableColumn(identifier: .init("app")))
        table.headerView = nil
        table.rowHeight = 34
        table.style = .plain
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.intercellSpacing = NSSize(width: 0, height: 0)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 238).isActive = true

        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])

        for (button, symbol, action) in [(addButton, "plus", #selector(showAddMenu)), (removeButton, "minus", #selector(removeSelected))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol == "plus" ? L("Add") : L("Remove"))
            button.bezelStyle = .smallSquare
            button.isBordered = false
            button.target = self
            button.action = action
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let restore = NSButton(title: L("Restore Defaults"), target: self, action: #selector(restoreDefaults))
        restore.isBordered = false
        restore.contentTintColor = .controlAccentColor
        restore.font = .systemFont(ofSize: 12)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let toolbar = UI.hstack([addButton, removeButton, spacer, restore], spacing: 2)

        let listCard = FormSection(rows: [scroll, padded(toolbar, 4)])
        let list = UI.vstack([indent(listHeader), listCard, indent(listFooter)], spacing: 6)
        UI.fillWidth(list)

        view = makeView([mode, list])
        observe([SettingsStore.didChange])
    }

    override func reload() {
        let s = store.settings
        modePopup.selectItem(at: s.mode == .allExceptExcluded ? 0 : 1)
        if s.mode == .allExceptExcluded {
            listHeader.stringValue = L("Never quit")
            listFooter.stringValue = L("These apps keep running even without windows. Good for music players, mail and chat apps.")
            emptyLabel.stringValue = L("Every app will be quit when its last window closes.")
        } else {
            listHeader.stringValue = L("Quit only these")
            listFooter.stringValue = L("Only these apps are quit when their last window closes. All other apps are left alone.")
            emptyLabel.stringValue = L("Add apps with the + button.")
        }
        items = s[keyPath: listKeyPath].map(AppInfo.init(bundleID:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        emptyLabel.isHidden = !items.isEmpty
        table.reloadData()
        updateRemoveButton()
    }

    private func updateRemoveButton() {
        removeButton.isEnabled = !table.selectedRowIndexes.isEmpty
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateRemoveButton() }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let icon = item.url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
        let image = NSImageView(image: icon)
        image.translatesAutoresizingMaskIntoConstraints = false
        image.widthAnchor.constraint(equalToConstant: 24).isActive = true
        image.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let name = UI.title(item.name)
        // Apps that aren't installed only have their bundle ID as a name.
        let detail = UI.title(item.url == nil ? L("not installed") : item.bundleID, size: 11)
        detail.textColor = .tertiaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UI.hstack([image, name, detail], spacing: 8)

        let cell = NSTableCellView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func modeChanged() {
        store.update { $0.mode = modePopup.indexOfSelectedItem == 1 ? .onlyIncluded : .allExceptExcluded }
    }

    @objc private func showAddMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: L("Running apps"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let listed = Set(store.settings[keyPath: listKeyPath])
        for app in AppInfo.runningRegularApps() where !listed.contains(app.bundleIdentifier!) {
            let item = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier!, action: #selector(addFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = app.bundleIdentifier
            item.image = app.icon.map { icon in
                let copy = icon.copy() as! NSImage
                copy.size = NSSize(width: 16, height: 16)
                return copy
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let browse = NSMenuItem(title: L("Choose App…"), action: #selector(browse), keyEquivalent: "")
        browse.target = self
        menu.addItem(browse)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: addButton.bounds.height + 4), in: addButton)
    }

    @objc private func addFromMenu(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        add([id])
    }

    @objc private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        add(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
    }

    private func add(_ ids: [String]) {
        let path = listKeyPath
        store.update { settings in
            for id in ids where !settings[keyPath: path].contains(id) {
                settings[keyPath: path].append(id)
            }
        }
    }

    @objc private func removeSelected() {
        let ids = Set(table.selectedRowIndexes.map { items[$0].bundleID })
        guard !ids.isEmpty else { return }
        let path = listKeyPath
        store.update { $0[keyPath: path].removeAll(where: ids.contains) }
    }

    @objc private func restoreDefaults() {
        let path = listKeyPath
        store.update { $0[keyPath: path] = TidySettings.default[keyPath: path] }
    }
}

// MARK: - Shortcuts

private final class ShortcutsPane: Pane {
    private let store: SettingsStore
    private var recorders: [HotkeyAction: HotkeyRecorder] = [:]

    init(store: SettingsStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        var rows: [NSView] = []
        for action in HotkeyAction.allCases {
            let recorder = HotkeyRecorder(hotkey: store.settings.hotkeys[action])
            recorder.onChange = { [weak self] hotkey in
                self?.store.update { $0.hotkeys[action] = hotkey }
            }
            recorders[action] = recorder
            let (symbol, color, title, subtitle) = Self.describe(action)
            rows.append(FormRow(icon: IconTile(symbol: symbol, color: color), title: title, subtitle: subtitle, accessory: recorder, textWidth: 250))
        }
        let section = FormSection(title: L("Global shortcuts"),
                                  footer: L("Click a button and press the keys. Press Delete to remove a shortcut or Esc to cancel."),
                                  rows: rows)
        view = makeView([section])
        observe([SettingsStore.didChange])
    }

    override func reload() {
        for (action, recorder) in recorders {
            recorder.hotkey = store.settings.hotkeys[action]
        }
    }

    static func describe(_ action: HotkeyAction) -> (String, NSColor, String, String) {
        switch action {
        case .toggleSessionPause:
            return ("pause.fill", .systemOrange, L("Pause or resume"), L("Stops quitting apps until you press it again or restart TidyDock."))
        case .toggleExcludeFrontmostApp:
            return ("hand.raised.fill", .systemRed, L("Never quit the front app"), L("Adds the app you're using to the “never quit” list, or removes it."))
        case .cleanNow:
            return ("sparkles", .systemBlue, L("Clean up now"), L("Quits every app that has no windows open right now."))
        }
    }
}

// MARK: - About

private final class AboutPane: Pane {
    private let updater: Updater
    private let autoSwitch = NSSwitch()

    init(updater: Updater) {
        self.updater = updater
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 88).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 88).isActive = true
        let name = UI.title("TidyDock", size: 22, weight: .bold)
        let versionLabel = UI.title(L("Version %@ (%@)", version, build), size: 12)
        versionLabel.textColor = .secondaryLabelColor
        let tagline = UI.wrapping(L("Quits apps that are left running without windows. Free and open source."), size: 13, width: 420, alignment: .center)

        let links = UI.hstack([
            UI.button(L("GitHub"), target: self, action: #selector(openRepo)),
            UI.button(L("Report a Problem"), target: self, action: #selector(reportIssue)),
        ], spacing: 10)

        let hero = UI.vstack([icon, name, versionLabel, tagline, links], spacing: 6, alignment: .centerX)
        hero.setCustomSpacing(12, after: icon)
        hero.setCustomSpacing(16, after: tagline)

        let updates: FormSection
        if updater.isAvailable {
            autoSwitch.state = updater.automaticallyChecks ? .on : .off
            autoSwitch.controlSize = .small
            autoSwitch.target = self
            autoSwitch.action = #selector(autoChanged)
            updates = FormSection(title: L("Updates"), rows: [
                FormRow(icon: IconTile(symbol: "arrow.triangle.2.circlepath", color: .systemBlue), title: L("Check automatically"), accessory: autoSwitch),
                FormRow(icon: IconTile(symbol: "arrow.down.circle.fill", color: .systemGreen), title: L("Check for updates now"),
                        accessory: UI.button(L("Check Now"), target: self, action: #selector(checkNow))),
            ])
        } else {
            updates = FormSection(title: L("Updates"), rows: [
                FormRow(icon: IconTile(symbol: "arrow.triangle.2.circlepath", color: .systemGray), title: L("Automatic updates are off in this build"),
                        subtitle: L("Download new versions from GitHub."),
                        accessory: UI.button(L("Releases"), target: self, action: #selector(openReleases))),
            ])
        }

        let footer = UI.title(L("MIT License · © 2026 Utku Meydan"), size: 11)
        footer.textColor = .tertiaryLabelColor

        let stack = UI.vstack([hero, updates, footer], spacing: 22, alignment: .centerX)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        updates.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        view = stack
    }

    @objc private func checkNow() { updater.checkForUpdates() }
    @objc private func autoChanged() { updater.automaticallyChecks = autoSwitch.state == .on }
    @objc private func openRepo() { NSWorkspace.shared.open(AppLinks.repository) }
    @objc private func openReleases() { NSWorkspace.shared.open(AppLinks.repository.appendingPathComponent("releases")) }
    @objc private func reportIssue() { NSWorkspace.shared.open(AppLinks.newIssue) }
}

enum AppLinks {
    static let repository = URL(string: "https://github.com/utkumeydan/TidyDock")!
    static let newIssue = URL(string: "https://github.com/utkumeydan/TidyDock/issues/new?template=bug_report.yml")!
}
