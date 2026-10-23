// Draws Resources/AppIcon.icns: run `swift scripts/make-icon.swift` from the repo root, then commit the .icns.
import AppKit

func draw(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size / 1024
        // Apple's grid: an 824 pt rounded square centred on a 1024 canvas, leaving room for the system shadow.
        let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.80, alpha: 1),
            NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.85, alpha: 1),
        ])!.draw(in: shape, angle: -60)

        let bar = CGRect(x: 190 * s, y: 230 * s, width: 644 * s, height: 150 * s)
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 40 * s, yRadius: 40 * s).fill()

        let colors: [NSColor] = [.systemOrange, .systemGreen, .systemPink]
        for (i, color) in colors.enumerated() {
            let x = (240 + CGFloat(i) * 130) * s
            color.setFill()
            NSBezierPath(roundedRect: CGRect(x: x, y: 262 * s, width: 96 * s, height: 86 * s), xRadius: 22 * s, yRadius: 22 * s).fill()
        }
        NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.80, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 250 * s, y: 244 * s, width: 76 * s, height: 10 * s), xRadius: 5 * s, yRadius: 5 * s).fill()

        NSColor.white.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: CGRect(x: 250 * s, y: 560 * s, width: 524 * s, height: 230 * s), xRadius: 34 * s, yRadius: 34 * s).fill()
        return true
    }
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(points * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels), pixelsHigh: Int(pixels), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(size: pixels).draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
