// Builds Support/AppIcon.icns from the logo artwork: masks it to a rounded square, places it on the
// macOS icon grid (824 px art inside a 1024 px canvas), then renders every iconset size.
// Usage: swift scripts/make-icon.swift Support/Resources/app-icon-source.png Support/AppIcon.icns
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let src = NSImage(contentsOfFile: args[1]),
      let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("usage: make-icon <source.png> <out.icns>") }

func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let s = CGFloat(px) / 1024
    let art = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    // Drop shadow like the system icons, then the artwork clipped to the rounded square.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 20 * s, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: art, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: art, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil))
    ctx.clip()
    ctx.draw(cg, in: art)
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", args[2]]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(args[2])" : "iconutil failed")
