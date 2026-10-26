import AppKit

// Small AppKit building blocks for a System Settings–style look:
// grouped cards with rows, colored icon tiles and switches.

enum UI {
    static let cardFill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.055)
            : NSColor(white: 1, alpha: 1)
    }
    static let cardBorder = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.08)
            : NSColor(white: 0, alpha: 0.08)
    }

    static func title(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    static func wrapping(_ text: String, size: CGFloat = 11, color: NSColor = .secondaryLabelColor, width: CGFloat, alignment: NSTextAlignment = .left) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.alignment = alignment
        field.preferredMaxLayoutWidth = width
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    static func vstack(_ views: [NSView], spacing: CGFloat = 4, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = alignment
        stack.spacing = spacing
        return stack
    }

    static func hstack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    /// Makes every arranged subview of a vertical stack as wide as the stack's content area.
    static func fillWidth(_ stack: NSStackView) {
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        }
    }

    static func switchControl(_ isOn: Bool, target: AnyObject, action: Selector) -> NSSwitch {
        let control = NSSwitch()
        control.state = isOn ? .on : .off
        control.target = target
        control.action = action
        control.controlSize = .small
        return control
    }

    static func button(_ title: String, target: AnyObject, action: Selector, primary: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .push
        if primary {
            button.keyEquivalent = "\r"
            button.bezelColor = .controlAccentColor
        }
        return button
    }

    static func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor) -> NSImageView {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        let view = NSImageView(image: image ?? NSImage())
        view.contentTintColor = color
        return view
    }
}

/// A rounded, colored square with a white SF Symbol, like the icons in System Settings.
final class IconTile: NSView {
    private let color: NSColor

    init(symbol: String, color: NSColor, size: CGFloat = 26) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = size * 0.24
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true

        let image = UI.symbol(symbol, size: size * 0.5, color: .white)
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: centerXAnchor),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // Resolve the color for the current appearance each time it changes.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }
}

/// One line in a card: optional icon, title and subtitle on the left, a control on the right.
final class FormRow: NSView {
    init(icon: IconTile? = nil, title: String, subtitle: String? = nil, accessory: NSView? = nil, textWidth: CGFloat = 340) {
        super.init(frame: .zero)
        let titleLabel = UI.title(title)
        var textViews: [NSView] = [titleLabel]
        if let subtitle {
            textViews.append(UI.wrapping(subtitle, width: textWidth))
        }
        let text = UI.vstack(textViews, spacing: 2)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var views: [NSView] = []
        if let icon { views.append(icon) }
        views.append(text)
        if let accessory {
            accessory.setContentHuggingPriority(.required, for: .horizontal)
            views.append(accessory)
        }
        let stack = UI.hstack(views, spacing: 10)
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A titled group of rows on a rounded card, with an optional footer note.
final class FormSection: NSView {
    init(title: String? = nil, footer: String? = nil, rows: [NSView]) {
        super.init(frame: .zero)

        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = 10
        card.borderWidth = 1
        card.borderColor = UI.cardBorder
        card.fillColor = UI.cardFill
        card.contentViewMargins = .zero
        card.titlePosition = .noTitle

        var cardViews: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                cardViews.append(separator)
            }
            cardViews.append(row)
        }
        let inner = UI.vstack(cardViews, spacing: 0)
        inner.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.contentView?.addSubview(inner)
        if let content = card.contentView {
            NSLayoutConstraint.activate([
                inner.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                inner.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                inner.topAnchor.constraint(equalTo: content.topAnchor),
                inner.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        for view in inner.arrangedSubviews {
            // Separators start at the text, like System Settings.
            let inset: CGFloat = view is NSBox ? 12 : 0
            view.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: inset).isActive = true
            view.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: view is NSBox ? -12 : 0).isActive = true
        }

        var views: [NSView] = []
        if let title {
            let header = UI.title(title, size: 13, weight: .semibold)
            views.append(indented(header))
        }
        views.append(card)
        if let footer {
            views.append(indented(UI.wrapping(footer, width: 480)))
        }
        let outer = UI.vstack(views, spacing: 6)
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        UI.fillWidth(outer)
    }

    private func indented(_ view: NSView) -> NSView {
        let wrapper = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 4),
            view.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -4),
            view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A small capsule with a colored dot, used for live status.
final class StatusPill: NSView {
    private let dot = NSView()
    private let label = UI.title("", size: 12, weight: .medium)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let stack = UI.hstack([dot, label], spacing: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var color: NSColor = .systemOrange

    func set(_ text: String, color: NSColor) {
        label.stringValue = text
        self.color = color
        needsDisplay = true
        needsLayout = true
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = color.cgColor
            layer?.backgroundColor = color.withAlphaComponent(0.15).cgColor
        }
    }
}
