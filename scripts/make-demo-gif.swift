// Draws the animated demo for the README: a window closes, its app lingers in
// the Dock, TidyDock quits it and shows the Undo notice.
//
// Usage: swift scripts/make-demo-gif.swift [en|tr]   → docs/demo-<lang>.gif
import AppKit
import ImageIO
import UniformTypeIdentifiers

let lang = CommandLine.arguments.dropFirst().first ?? "en"
let text: [String: [String: String]] = [
    "en": [
        "window": "Notes.txt",
        "step1": "You close the last window…",
        "step2": "…but the app keeps running in the Dock.",
        "step3": "TidyDock quits it for you.",
        "toastTitle": "Quit TextEdit",
        "toastDetail": "No windows were open · 64 MB freed",
        "undo": "Undo",
    ],
    "tr": [
        "window": "Notlar.txt",
        "step1": "Son pencereyi kapatıyorsunuz…",
        "step2": "…ama uygulama Dock'ta çalışmaya devam ediyor.",
        "step3": "TidyDock onu sizin yerinize kapatır.",
        "toastTitle": "TextEdit kapatıldı",
        "toastDetail": "Açık penceresi yoktu · 64 MB boşaltıldı",
        "undo": "Geri Al",
    ],
]
guard let t = text[lang] else { fatalError("Unknown language \(lang)") }

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let W: CGFloat = 720, H: CGFloat = 420
let fps = 15.0
let duration = 6.4

/// Looks apps up by bundle ID so symlinked locations don't add an alias badge.
func icon(_ bundleID: String) -> NSImage {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return NSImage() }
    return NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
}
let tidyIcon = NSImage(contentsOf: root.appendingPathComponent("Support/AppIcon.icns")) ?? NSImage()
let dockApps: [NSImage] = [
    icon("com.apple.finder"),
    icon("com.apple.Safari"),
    icon("com.apple.Notes"),
    icon("com.apple.Music"),
    icon("com.apple.TextEdit"),
    icon("com.apple.Preview"),
]
let textEditIndex = 4

// MARK: - Timing helpers

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
/// 0→1 progress of `time` between `start` and `end`.
func progress(_ time: Double, _ start: Double, _ end: Double) -> Double { clamp((time - start) / (end - start)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func lerp(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat { a + (b - a) * CGFloat(x) }

// MARK: - Drawing

func drawText(_ string: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight = .regular,
              color: NSColor = .white, centered: Bool = false, alpha: CGFloat = 1) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35 * alpha)
    shadow.shadowBlurRadius = 6
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color.withAlphaComponent(alpha),
        .shadow: shadow,
    ]
    let s = NSAttributedString(string: string, attributes: attrs)
    let x = centered ? point.x - s.size().width / 2 : point.x
    s.draw(at: NSPoint(x: x, y: point.y))
}

func roundedRect(_ rect: NSRect, _ radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func drawCursor(at p: NSPoint, pressed: Bool) {
    let s: CGFloat = pressed ? 0.9 : 1
    let path = NSBezierPath()
    path.move(to: NSPoint(x: p.x, y: p.y))
    path.line(to: NSPoint(x: p.x, y: p.y - 22 * s))
    path.line(to: NSPoint(x: p.x + 6 * s, y: p.y - 16 * s))
    path.line(to: NSPoint(x: p.x + 11 * s, y: p.y - 26 * s))
    path.line(to: NSPoint(x: p.x + 15 * s, y: p.y - 24 * s))
    path.line(to: NSPoint(x: p.x + 10 * s, y: p.y - 14 * s))
    path.line(to: NSPoint(x: p.x + 17 * s, y: p.y - 14 * s))
    path.close()
    NSColor.black.setFill()
    path.fill()
    NSColor.white.setStroke()
    path.lineWidth = 1.5
    path.stroke()
}

func frame(at time: Double) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Wallpaper
    NSGradient(colors: [
        NSColor(red: 0.16, green: 0.20, blue: 0.45, alpha: 1),
        NSColor(red: 0.36, green: 0.24, blue: 0.62, alpha: 1),
        NSColor(red: 0.85, green: 0.45, blue: 0.55, alpha: 1),
    ])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)

    // Menu bar with the TidyDock icon.
    NSColor.white.withAlphaComponent(0.18).setFill()
    NSRect(x: 0, y: H - 24, width: W, height: 24).fill()
    let iconCenter = NSPoint(x: W - 120, y: H - 12)
    let flash = progress(time, 2.25, 2.75)
    let sparkle = flash > 0 && flash < 1 ? "sparkles" : "dock.rectangle"
    if let symbol = NSImage(systemSymbolName: sparkle, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) {
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(at: NSPoint(x: iconCenter.x - symbol.size.width / 2, y: iconCenter.y - symbol.size.height / 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }
    drawText("9:41", at: NSPoint(x: W - 52, y: H - 19), size: 12, weight: .medium)

    // The TextEdit window closes when the cursor clicks it.
    let close = ease(progress(time, 1.15, 1.45))
    if close < 1 {
        let scale = lerp(1, 0.9, close)
        let win = NSRect(x: 0, y: 0, width: 380 * scale, height: 220 * scale)
        let origin = NSPoint(x: (W - win.width) / 2, y: 150 + (220 - win.height) / 2)
        let rect = NSRect(origin: origin, size: win.size)
        let alpha = 1 - CGFloat(close)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35 * alpha)
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()
        roundedRect(rect, 12, fill: NSColor(white: 0.98, alpha: alpha))
        NSGraphicsContext.restoreGraphicsState()
        // Title bar and traffic lights.
        let lights: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
        for (i, color) in lights.enumerated() {
            color.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.minX + 14 + CGFloat(i) * 18, y: rect.maxY - 22, width: 11, height: 11)).fill()
        }
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                         .foregroundColor: NSColor(white: 0.3, alpha: alpha)]
        let title = NSAttributedString(string: t["window"]!, attributes: titleAttrs)
        title.draw(at: NSPoint(x: rect.midX - title.size().width / 2, y: rect.maxY - 24))
        // A few lines of "text".
        for line in 0..<5 {
            NSColor(white: 0.82, alpha: alpha).setFill()
            let width = [0.85, 0.7, 0.9, 0.6, 0.75][line] * (rect.width - 40)
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 20, y: rect.maxY - 58 - CGFloat(line) * 24, width: width, height: 9), xRadius: 4, yRadius: 4).fill()
        }
    }

    // Dock: TextEdit fades away once TidyDock quits it.
    let quit = ease(progress(time, 2.3, 2.8))
    let iconSize: CGFloat = 46, gap: CGFloat = 10
    let teWidth = lerp(iconSize + gap, 0, quit)
    let dockWidth = CGFloat(dockApps.count - 1) * (iconSize + gap) + teWidth + 14
    let dockRect = NSRect(x: (W - dockWidth) / 2, y: 10, width: dockWidth, height: iconSize + 20)
    roundedRect(dockRect, 18, fill: NSColor.white.withAlphaComponent(0.22), stroke: NSColor.white.withAlphaComponent(0.25))
    var x = dockRect.minX + 12
    for (i, image) in dockApps.enumerated() {
        let isTextEdit = i == textEditIndex
        let size = isTextEdit ? lerp(iconSize, 4, quit) : iconSize
        let alpha = isTextEdit ? 1 - CGFloat(quit) : 1
        let y = dockRect.minY + 12 + (iconSize - size) / 2
        image.draw(in: NSRect(x: x + (iconSize - size) / 2, y: y, width: size, height: size),
                   from: .zero, operation: .sourceOver, fraction: alpha)
        // Running indicator dots under open apps.
        if [0, 1, textEditIndex].contains(i) {
            NSColor.white.withAlphaComponent(0.9 * alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: x + iconSize / 2 - 2, y: dockRect.minY + 4, width: 4, height: 4)).fill()
        }
        x += isTextEdit ? teWidth : iconSize + gap
    }
    // Pulse a ring around the lingering TextEdit icon.
    let linger = progress(time, 1.6, 2.2)
    if linger > 0, quit == 0 {
        let teX = dockRect.minX + 12 + CGFloat(textEditIndex) * (iconSize + gap)
        let pulse = CGFloat(sin(linger * .pi))
        NSColor.white.withAlphaComponent(0.8 * pulse).setStroke()
        let ring = NSBezierPath(roundedRect: NSRect(x: teX - 5, y: dockRect.minY + 7, width: iconSize + 10, height: iconSize + 10), xRadius: 14, yRadius: 14)
        ring.lineWidth = 2.5
        ring.stroke()
    }

    // Captions.
    let captions: [(String, Double, Double)] = [(t["step1"]!, 0.2, 1.5), (t["step2"]!, 1.5, 2.3), (t["step3"]!, 2.3, 6.4)]
    for (caption, start, end) in captions {
        let fadeIn = progress(time, start, start + 0.25)
        let fadeOut = end >= duration ? 0 : progress(time, end - 0.2, end)
        let alpha = CGFloat(fadeIn * (1 - fadeOut))
        if alpha > 0 {
            drawText(caption, at: NSPoint(x: W / 2, y: 112), size: 20, weight: .semibold, centered: true, alpha: alpha)
        }
    }

    // The Undo notice under the menu bar icon.
    let toastIn = ease(progress(time, 2.7, 3.0))
    if toastIn > 0 {
        let size = NSSize(width: 370, height: 58)
        let rect = NSRect(x: min(iconCenter.x - size.width / 2, W - size.width - 10),
                          y: H - 30 - size.height + lerp(10, 0, toastIn), width: size.width, height: size.height)
        let alpha = CGFloat(toastIn)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3 * alpha)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        roundedRect(rect, 14, fill: NSColor(white: 0.96, alpha: 0.97 * alpha))
        NSGraphicsContext.restoreGraphicsState()
        dockApps[textEditIndex].draw(in: NSRect(x: rect.minX + 12, y: rect.minY + 13, width: 32, height: 32),
                                     from: .zero, operation: .sourceOver, fraction: alpha)
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                         .foregroundColor: NSColor(white: 0.1, alpha: alpha)]
        NSAttributedString(string: t["toastTitle"]!, attributes: titleAttrs).draw(at: NSPoint(x: rect.minX + 54, y: rect.minY + 30))
        let detailAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11),
                                                          .foregroundColor: NSColor(white: 0.4, alpha: alpha)]
        NSAttributedString(string: t["toastDetail"]!, attributes: detailAttrs).draw(at: NSPoint(x: rect.minX + 54, y: rect.minY + 13))
        let undo = NSAttributedString(string: t["undo"]!, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                                        .foregroundColor: NSColor(white: 0.15, alpha: alpha)])
        let button = NSRect(x: rect.maxX - undo.size().width - 32, y: rect.minY + 17, width: undo.size().width + 20, height: 24)
        roundedRect(button, 6, fill: NSColor(white: 0.86, alpha: alpha))
        undo.draw(at: NSPoint(x: button.minX + 10, y: button.minY + 4))
    }

    // The cursor glides to the window's close button and clicks it.
    let move = ease(progress(time, 0.3, 1.0))
    let start = NSPoint(x: W / 2 + 120, y: 120)
    let target = NSPoint(x: (W - 380) / 2 + 19, y: 150 + 220 - 18)
    let cursorFade = 1 - progress(time, 1.7, 2.0)
    if cursorFade > 0 {
        let p = NSPoint(x: lerp(start.x, target.x, move), y: lerp(start.y, target.y, move))
        drawCursor(at: p, pressed: time > 1.0 && time < 1.2)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

// MARK: - Encode

let output = root.appendingPathComponent("docs/demo-\(lang).gif")
let frameCount = Int(duration * fps)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
    fatalError("Cannot write \(output.path)")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for index in 0..<frameCount {
    let time = Double(index) / fps
    // Hold the final frame a little longer before looping.
    let delay = index == frameCount - 1 ? 1.5 : 1 / fps
    CGImageDestinationAddImage(destination, frame(at: time), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("GIF encoding failed") }
print("Wrote \(output.path)")
