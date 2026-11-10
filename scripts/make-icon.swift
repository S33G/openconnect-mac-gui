import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let master = NSImage(size: NSSize(width: 1024, height: 1024))
master.lockFocus()
let rect = NSRect(x: 70, y: 70, width: 884, height: 884)
let path = NSBezierPath(roundedRect: rect, xRadius: 196, yRadius: 196)
NSGradient(starting: NSColor(calibratedWhite: 0.32, alpha: 1),
           ending: NSColor(calibratedWhite: 0.12, alpha: 1))!.draw(in: path, angle: -45)
// Original vector artwork; no vendor logos or SF Symbol artwork in the app icon.
let transform = NSAffineTransform()
transform.translateX(by: 512, yBy: 512)
transform.rotate(byDegrees: 42)
transform.translateX(by: -512, yBy: -512)
NSColor.white.setStroke()
for x in [230.0, 434.0] {
    let link = NSBezierPath(roundedRect: NSRect(x: x, y: 396, width: 360, height: 232), xRadius: 116, yRadius: 116)
    link.transform(using: transform as AffineTransform)
    link.lineWidth = 54
    link.stroke()
}
let indicator = NSBezierPath(ovalIn: NSRect(x: 714, y: 190, width: 82, height: 82))
NSColor(red: 0.26, green: 0.86, blue: 0.58, alpha: 1).setFill()
indicator.fill()
master.unlockFocus()
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
