import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func render(size: Int) -> Data? {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = rect.insetBy(dx: CGFloat(size) * 0.05, dy: CGFloat(size) * 0.05)
    let path = NSBezierPath(roundedRect: inset, xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.93, green: 0.18, blue: 0.22, alpha: 1),
                              ending: NSColor(calibratedRed: 0.55, green: 0.05, blue: 0.12, alpha: 1))
    gradient?.draw(in: path, angle: -70)
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.52, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let symbolSize = tinted.size
        let origin = NSPoint(x: (CGFloat(size) - symbolSize.width) / 2, y: (CGFloat(size) - symbolSize.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    bitmap.size = NSSize(width: size, height: size)
    return bitmap.representation(using: .png, properties: [:])
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"), (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"), (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (size, name) in sizes {
    guard let data = render(size: size) else { continue }
    try? data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}
