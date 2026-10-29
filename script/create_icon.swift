import AppKit

// Reproducible native artwork; no third-party images, fonts or icon licenses.
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 22
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor(calibratedRed: 0.24, green: 0.19, blue: 0.65, alpha: 1).setFill(); tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(colors: [NSColor(calibratedRed: 0.33, green: 0.40, blue: 0.98, alpha: 1),
                    NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.60, alpha: 1)])!.draw(in: tile, angle: -60)
NSColor.white.withAlphaComponent(0.22).setStroke(); tile.lineWidth = 3; tile.stroke()

let paper = NSBezierPath(roundedRect: NSRect(x: 252, y: 214, width: 500, height: 612), xRadius: 48, yRadius: 48)
NSGraphicsContext.saveGraphicsState()
let paperShadow = NSShadow(); paperShadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
paperShadow.shadowOffset = NSSize(width: 0, height: -14); paperShadow.shadowBlurRadius = 28; paperShadow.set()
NSColor(calibratedWhite: 0.98, alpha: 1).setFill(); paper.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(calibratedRed: 0.92, green: 0.91, blue: 1, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 252, y: 720, width: 500, height: 106), xRadius: 40, yRadius: 40).fill()
for x in [334, 500, 666] {
    NSColor(calibratedRed: 0.32, green: 0.28, blue: 0.74, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 770, width: 24, height: 90), xRadius: 12, yRadius: 12).fill()
}
for (y, width) in [(624, 320), (534, 258), (444, 200)] {
    NSColor(calibratedRed: 0.55, green: 0.53, blue: 0.74, alpha: y == 624 ? 0.85 : 0.38).setFill()
    NSBezierPath(roundedRect: NSRect(x: 324, y: y, width: width, height: 28), xRadius: 14, yRadius: 14).fill()
}
let badgeRect = NSRect(x: 572, y: 160, width: 290, height: 290)
let badge = NSBezierPath(ovalIn: badgeRect)
NSGraphicsContext.saveGraphicsState(); paperShadow.set()
NSColor(calibratedRed: 0.22, green: 0.80, blue: 0.60, alpha: 1).setFill(); badge.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor.white.setStroke()
let ring = NSBezierPath(ovalIn: badgeRect.insetBy(dx: 66, dy: 66)); ring.lineWidth = 17; ring.stroke()
NSColor.white.setFill(); NSBezierPath(ovalIn: badgeRect.insetBy(dx: 128, dy: 128)).fill()
NSGraphicsContext.restoreGraphicsState()

let path = CommandLine.arguments[1]
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
