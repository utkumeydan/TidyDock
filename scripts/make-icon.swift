// Draws the app icon and writes Support/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("TidyDock.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Rounded square background with the macOS icon grid margins.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1), NSColor(red: 0.36, green: 0.30, blue: 0.92, alpha: 1)])!
        .draw(in: path, angle: -90)

    // A dock shelf with three app tiles, the last one fading out.
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: NSRect(x: 210 * s, y: 250 * s, width: 604 * s, height: 70 * s), xRadius: 35 * s, yRadius: 35 * s).fill()
    for (i, alpha) in [1.0, 1.0, 0.35].enumerated() {
        NSColor.white.withAlphaComponent(alpha).setFill()
        let x = (250 + CGFloat(i) * 190) * s
        NSBezierPath(roundedRect: NSRect(x: x, y: 360 * s, width: 150 * s, height: 150 * s), xRadius: 34 * s, yRadius: 34 * s).fill()
    }
    // A sparkle above the faded tile: "tidied up".
    NSColor.white.setFill()
    let star = NSBezierPath()
    let c = NSPoint(x: 705 * s, y: 650 * s)
    for k in 0..<8 {
        let r = (k % 2 == 0 ? 95 : 26) * s
        let a = CGFloat(k) * .pi / 4 + .pi / 2
        let p = NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
        k == 0 ? star.move(to: p) : star.line(to: p)
    }
    star.close()
    star.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}

let output = root.appendingPathComponent("Support/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
