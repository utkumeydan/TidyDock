import AppKit
import ApplicationServices
import TidyDockCore

/// The first-launch walkthrough: what TidyDock does, the Accessibility permission, and a quick setup.
final class OnboardingWindowController: NSWindowController {
    enum Page: Int { case welcome, permission, setup }

    static let completedKey = "onboarding.completed"
    static var hasCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    private let store: SettingsStore
    private let onAccessGranted: () -> Void
    private let onFinish: () -> Void

    private let container = NSView()
    private let dots = UI.hstack([], spacing: 7)
    private let backButton = NSButton(title: L("Back"), target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let statusPill = StatusPill()
    private var loginSwitch: NSSwitch?
    private var page: Page = .welcome
    private var timer: Timer?
    private var reportedAccess = false

    private let width: CGFloat = 600
    private let height: CGFloat = 560

    init(store: SettingsStore, onAccessGranted: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.store = store
        self.onAccessGranted = onAccessGranted
        self.onFinish = onFinish

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = L("Welcome to TidyDock")
        super.init(window: window)
        buildChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(at page: Page, watchAccess: Bool = true) {
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        go(to: page, animated: false)
        if watchAccess { startWatchingAccess() }
    }

    // MARK: - Layout

    private func buildChrome() {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        window?.contentView = background

        container.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(container)

        backButton.bezelStyle = .push
        backButton.target = self
        backButton.action = #selector(back)
        nextButton.bezelStyle = .push
        nextButton.keyEquivalent = "\r"
        nextButton.bezelColor = .controlAccentColor
        nextButton.target = self
        nextButton.action = #selector(next)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let footer = UI.hstack([dots, spacer, backButton, nextButton], spacing: 10)
        footer.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(footer)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: background.topAnchor, constant: 36),
            container.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 40),
            container.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -40),
            container.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 28),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -24),
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -20),
            background.widthAnchor.constraint(equalToConstant: width),
            background.heightAnchor.constraint(equalToConstant: height),
        ])
    }

    private func go(to newPage: Page, animated: Bool = true) {
        page = newPage
        let content: NSView
        switch newPage {
        case .welcome: content = welcomePage()
        case .permission: content = permissionPage()
        case .setup: content = setupPage()
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        let old = container.subviews
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            content.widthAnchor.constraint(equalTo: container.widthAnchor),
        ])
        if animated {
            content.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                content.animator().alphaValue = 1
                old.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { old.forEach { $0.removeFromSuperview() } })
        } else {
            old.forEach { $0.removeFromSuperview() }
        }
        updateFooter()
    }

    private func updateFooter() {
        dots.setViews((0..<3).map { index in
            let dot = NSView()
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3.5
            // Resolve the dynamic colors for this window's light or dark appearance.
            (window?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance {
                dot.layer?.backgroundColor = (index == page.rawValue ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
            }
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: index == page.rawValue ? 18 : 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
            return dot
        }, in: .leading)

        backButton.isHidden = page == .welcome
        switch page {
        case .welcome:
            nextButton.title = L("Get Started")
        case .permission:
            nextButton.title = Permissions.isTrusted ? L("Continue") : L("Open System Settings")
        case .setup:
            nextButton.title = L("Start TidyDock")
        }
    }

    // MARK: - Pages

    private func heroIcon(size: CGFloat) -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: size).isActive = true
        icon.heightAnchor.constraint(equalToConstant: size).isActive = true
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        icon.shadow = shadow
        return icon
    }

    private func headline(_ title: String, _ subtitle: String) -> [NSView] {
        let titleLabel = UI.title(title, size: 26, weight: .bold)
        titleLabel.alignment = .center
        let subtitleLabel = UI.wrapping(subtitle, size: 14, color: .secondaryLabelColor, width: 460, alignment: .center)
        return [titleLabel, subtitleLabel]
    }

    private func feature(_ symbol: String, _ color: NSColor, _ title: String, _ text: String) -> NSView {
        let titleLabel = UI.title(title, size: 13, weight: .semibold)
        let body = UI.wrapping(text, size: 12, width: 420)
        let row = UI.hstack([IconTile(symbol: symbol, color: color, size: 34), UI.vstack([titleLabel, body], spacing: 2)], spacing: 14)
        row.alignment = .top
        return row
    }

    private func welcomePage() -> NSView {
        let features = UI.vstack([
            feature("xmark.app.fill", .systemBlue, L("Quits apps when you close the last window"),
                    L("Gently, like ⌘Q. Apps still ask before you lose unsaved work.")),
            feature("checkmark.shield.fill", .systemGreen, L("Never quits the wrong thing"),
                    L("Leaves menu bar apps alone, and keeps apps with windows on other desktops or minimized.")),
            feature("slider.horizontal.3", .systemOrange, L("You stay in control"),
                    L("Exclude apps, set a delay, pause with a shortcut, or quit apps you haven't used in hours.")),
        ], spacing: 16)
        let views = [heroIcon(size: 96)] + headline(L("Keep your Dock tidy"), L("Closing an app's last window usually leaves it running. TidyDock quits it for you, so your Dock only shows what you're using.")) + [features]
        let stack = UI.vstack(views, spacing: 14, alignment: .centerX)
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[0])
        stack.setCustomSpacing(26, after: stack.arrangedSubviews[2])
        return stack
    }

    private func permissionPage() -> NSView {
        let steps = UI.vstack([
            step(1, L("Click “Open System Settings” below.")),
            step(2, L("Turn on TidyDock in the Accessibility list.")),
            step(3, L("Come back here. This page moves on by itself.")),
        ], spacing: 10)

        let privacy = UI.hstack([
            privacyBadge("eye.slash.fill", L("Doesn't read window contents")),
            privacyBadge("network.slash", L("No tracking or analytics")),
            privacyBadge("lock.fill", L("Open source")),
        ], spacing: 18)

        let hint = UI.wrapping(L("TidyDock not in the list? Click + and choose it from the Applications folder. After an update, remove it with − and add it again."),
                               size: 11, color: .tertiaryLabelColor, width: 460, alignment: .center)

        updateStatusPill()
        let views = [IconTile(symbol: "hand.raised.fill", color: .systemBlue, size: 72)]
            + headline(L("Allow Accessibility access"), L("TidyDock uses it only to count each app's open windows. That's how it knows when the last one closes."))
            + [statusPill, steps, privacy, hint]
        let stack = UI.vstack(views, spacing: 14, alignment: .centerX)
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[0])
        stack.setCustomSpacing(22, after: steps)
        return stack
    }

    private func step(_ number: Int, _ text: String) -> NSView {
        let badge = NumberBadge(number)
        let row = UI.hstack([badge, UI.title(text, size: 13)], spacing: 10)
        row.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return row
    }

    private func privacyBadge(_ symbol: String, _ text: String) -> NSView {
        UI.hstack([UI.symbol(symbol, size: 11, color: .secondaryLabelColor), UI.title(text, size: 11)], spacing: 5)
    }

    private func updateStatusPill() {
        if Permissions.isTrusted {
            statusPill.set(L("Access granted"), color: .systemGreen)
        } else {
            statusPill.set(L("Waiting for permission…"), color: .systemOrange)
        }
    }

    private func setupPage() -> NSView {
        let login = UI.switchControl(true, target: self, action: #selector(noop))
        loginSwitch = login

        let delay = Choices.delayPopup(selected: store.settings.quitDelay, target: self, action: #selector(delayChanged(_:)))
        let idle = UI.switchControl(store.settings.idleQuitEnabled, target: self, action: #selector(idleChanged(_:)))

        let section = FormSection(rows: [
            FormRow(icon: IconTile(symbol: "power", color: .systemGreen), title: L("Open at login"),
                    subtitle: L("Recommended, so your Dock stays tidy after a restart."), accessory: login),
            FormRow(icon: IconTile(symbol: "timer", color: .systemBlue), title: L("Quit delay"),
                    subtitle: L("How long to wait after the last window closes."), accessory: delay),
            FormRow(icon: IconTile(symbol: "moon.zzz.fill", color: .systemIndigo), title: L("Quit idle apps"),
                    subtitle: L("Also quit apps you haven't used for 2 hours. You can change this later."), accessory: idle),
        ])

        let menuIcon = UI.symbol("dock.rectangle", size: 15, weight: .regular, color: .labelColor)
        let hint = UI.hstack([menuIcon, UI.wrapping(L("TidyDock lives in the menu bar. Click its icon to see recently quit apps, pause it, or open Settings."), size: 12, width: 420)], spacing: 10)

        let views = [IconTile(symbol: "checkmark", color: .systemGreen, size: 72)]
            + headline(L("Almost done"), L("Pick a few defaults. Everything can be changed later in Settings."))
            + [section, hint]
        let stack = UI.vstack(views, spacing: 14, alignment: .centerX)
        stack.setCustomSpacing(18, after: stack.arrangedSubviews[0])
        stack.setCustomSpacing(22, after: stack.arrangedSubviews[2])
        section.widthAnchor.constraint(equalToConstant: 500).isActive = true
        return stack
    }

    // MARK: - Actions

    @objc private func noop() {}

    @objc private func delayChanged(_ sender: NSPopUpButton) {
        store.update { $0.quitDelay = Choices.delay(from: sender) }
    }

    @objc private func idleChanged(_ sender: NSSwitch) {
        store.update { $0.idleQuitEnabled = sender.state == .on }
    }

    @objc private func back() {
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        go(to: previous)
    }

    @objc private func next() {
        switch page {
        case .welcome:
            go(to: Permissions.isTrusted ? .setup : .permission)
        case .permission:
            if Permissions.isTrusted {
                go(to: .setup)
            } else {
                Permissions.requestAccessibility()
            }
        case .setup:
            if loginSwitch?.state == .on, !LaunchAtLogin.isEnabled { LaunchAtLogin.set(true) }
            if loginSwitch?.state == .off, LaunchAtLogin.isEnabled { LaunchAtLogin.set(false) }
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            timer?.invalidate()
            close()
            onFinish()
        }
    }

    private func startWatchingAccess() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = Permissions.isTrusted
            if self.page == .permission {
                self.updateStatusPill()
                self.updateFooter()
            }
            guard trusted, !self.reportedAccess else { return }
            self.reportedAccess = true
            self.onAccessGranted()
            if self.page == .permission {
                // Give the green status a moment to register, then move on.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    NSApp.activate(ignoringOtherApps: true)
                    if self.page == .permission { self.go(to: .setup) }
                }
            }
        }
    }

    override func close() {
        timer?.invalidate()
        timer = nil
        super.close()
    }
}

/// An accent-colored circle with a number centered in it.
private final class NumberBadge: NSView {
    init(_ number: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true

        let label = UI.title("\(number)", size: 12, weight: .bold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }
}

enum Permissions {
    private static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static var isTrusted: Bool { ScreenshotMode.scene != nil || AXIsProcessTrusted() }

    /// Shows the system prompt (which also adds TidyDock to the list) and opens the settings pane.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(accessibilitySettingsURL)
    }
}
