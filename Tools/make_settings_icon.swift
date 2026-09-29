// Draws the settings app icon (AppIcon.icns): a rounded square with 한 large
// and A / あ small — the three modes NRIME switches between.
// Usage: swift Tools/make_settings_icon.swift NRIMESettings/Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments[1]

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS app icon grid: an 824-point body inside 1024, corner radius 185.
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                            xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.80, alpha: 1),
        NSColor(calibratedRed: 0.83, green: 0.32, blue: 0.52, alpha: 1),
    ])!.draw(in: body, angle: -90)

    func draw(_ text: String, size: CGFloat, weight: NSFont.Weight,
              centerX: CGFloat, centerY: CGFloat, alpha: CGFloat = 1) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        ])
        let bounds = string.size()
        string.draw(at: NSPoint(x: centerX - bounds.width / 2, y: centerY - bounds.height / 2))
    }
    draw("한", size: 420, weight: .bold, centerX: 512, centerY: 585)
    draw("A", size: 170, weight: .semibold, centerX: 372, centerY: 255, alpha: 0.9)
    draw("あ", size: 170, weight: .semibold, centerX: 652, centerY: 255, alpha: 0.9)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("nrime-settings.iconset")
try? fileManager.removeItem(at: iconset)
try! fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try! iconutil.run()
iconutil.waitUntilExit()
try? fileManager.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(iconutil.terminationStatus)")
}
print("wrote \(output)")
