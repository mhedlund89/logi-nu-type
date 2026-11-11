// Builds Support/Resources/keyboard-top.png from the keyboard illustration sheet: crop the top view,
// white out leader-line stubs from the sheet's callouts, grayscale, and lift the paper to pure white.
// Usage: swift scripts/make-keyboard.swift Support/Resources/keyboard-sheet.png Support/Resources/keyboard-top.png
import AppKit
import CoreImage

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard let src = CIImage(contentsOf: input) else { fatalError("can't read \(input.path)") }
let H = src.extent.height
// Crop in top-left coordinates: x 54, y 260, 654 × 212.
let W = 654.0, CH = 212.0
let crop = CGRect(x: 54, y: H - 260 - CH, width: W, height: CH)
var img = src.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
img = img.applyingFilter("CIPhotoEffectMono")
img = img.applyingFilter("CIToneCurve", parameters: [
    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0.3, y: 0.12),
    "inputPoint2": CIVector(x: 0.55, y: 0.5), "inputPoint3": CIVector(x: 0.8, y: 1), "inputPoint4": CIVector(x: 1, y: 1)])

// Leader lines and dimension ticks that belong to the sheet, not the keyboard (top-left coordinates).
let masks = [CGRect(x: 0, y: 0, width: W, height: 6),          // above the logo bump
             CGRect(x: 0, y: 0, width: 17, height: 21),         // beside the bump, left
             CGRect(x: 333, y: 9, width: 12, height: 4),        // callout 6 leader inside the bump
             CGRect(x: 611, y: 9, width: 15, height: 9),        // callout 10 leader inside the bump
             CGRect(x: 626, y: 0, width: 28, height: 22),       // beside the bump, right (callout 10)
             CGRect(x: 0, y: 22, width: 4, height: CH - 22),    // left dimension ticks
             CGRect(x: 0, y: CH - 5, width: W, height: 5)]      // stubs below the case
let white = CIImage(color: .white)
for m in masks {
    img = white.cropped(to: CGRect(x: m.minX, y: CH - m.maxY, width: m.width, height: m.height)).composited(over: img)
}
let ctx = CIContext()
guard let cg = ctx.createCGImage(img, from: CGRect(x: 0, y: 0, width: W, height: CH)),
      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError("render failed") }
try png.write(to: output)
print("wrote \(output.path)")
