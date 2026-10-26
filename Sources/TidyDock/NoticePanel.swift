import AppKit

/// A small floating card under the menu bar icon: "Excel quit · Undo", or a suggestion with two buttons.
final class NoticePanel {
    struct Action {
        let title: String
        let isPrimary: Bool
        let handler: () -> Void
    }

    /// Where to show the card, usually the status item's frame on screen.
    var anchor: () -> NSRect? = { nil }

    private var panel: NSPanel?
    private var hideTimer: Timer?
    private let textWidth: CGFloat = 220

    func show(icon: NSImage?, title: String, detail: String?, actions: [Action], duration: TimeInterval) {
        hide(animated: false)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        // A mask image (not a layer corner radius) keeps the window itself rounded, shadow included.
        background.maskImage = Self.roundedMask(radius: 14)
        panel.contentView = background

        let iconView = NSImageView(image: icon ?? NSApp.applicationIconImage)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 32).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let titleLabel = UI.wrapping(title, size: 13, color: .labelColor, width: textWidth)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        var texts: [NSView] = [titleLabel]
        if let detail {
            texts.append(UI.wrapping(detail, size: 11, width: textWidth))
        }
        // A fixed text width lets wrapped lines report their real height.
        let text = UI.vstack(texts, spacing: 2)
        text.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        for label in texts { label.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true }

        let buttons = actions.map { action -> NSButton in
            let button = ClosureButton(title: action.title) { [weak self] in
                action.handler()
                self?.hide(animated: true)
            }
            button.bezelStyle = .push
            button.controlSize = .small
            if action.isPrimary { button.bezelColor = .controlAccentColor }
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            return button
        }
        let buttonStack = UI.vstack(buttons, spacing: 4, alignment: .trailing)

        let row = UI.hstack([iconView, text, buttonStack], spacing: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: background.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
        ])
        background.layoutSubtreeIfNeeded()
        let size = background.fittingSize

        // Just below the menu bar icon, kept on screen.
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let anchorRect = anchor() ?? NSRect(x: screen.maxX - 40, y: screen.maxY, width: 0, height: 0)
        var x = anchorRect.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let y = anchorRect.minY - size.height - 8
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide(animated: true)
        }
    }

    func hide(animated: Bool) {
        hideTimer?.invalidate()
        hideTimer = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

extension NoticePanel {
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// An NSButton that runs a closure, so callers don't need a target object.
private final class ClosureButton: NSButton {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(run)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
