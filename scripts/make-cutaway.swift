// Builds Support/Resources/mouse-cutaway.png from the full illustration sheet:
// crop the centre view, mask fragments of neighbouring views, grayscale, and lift the paper to pure white.
// Usage: swift scripts/make-cutaway.swift Support/Resources/mouse-sheet.png Support/Resources/mouse-cutaway.png
import AppKit
import CoreImage

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard let src = CIImage(contentsOf: input) else { fatalError("can't read \(input.path)") }
let H = src.extent.height
// Crop in top-left coordinates: x 20, y 338, 872 × 536 (Core Image's origin is bottom-left).
let W = 872.0, CH = 536.0
let crop = CGRect(x: 20, y: H - 338 - CH, width: W, height: CH)
var img = src.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))

// Grayscale, then a tone curve that maps the textured paper (~0.8+) to white and keeps ink black.
img = img.applyingFilter("CIPhotoEffectMono")
img = img.applyingFilter("CIToneCurve", parameters: [
    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0.3, y: 0.12),
    "inputPoint2": CIVector(x: 0.55, y: 0.5), "inputPoint3": CIVector(x: 0.78, y: 1), "inputPoint4": CIVector(x: 1, y: 1)])

// White out fragments of other views' labels (top-left coordinates within the crop).
// Top: the "(スラスター)" label of the view above. Bottom: a label of the view below.
let masks = [CGRect(x: 170, y: 0, width: 156, height: 34), CGRect(x: 300, y: 516, width: 240, height: 20)]
var white = CIImage(color: .white)
for m in masks {
    let r = CGRect(x: m.minX, y: CH - m.maxY, width: m.width, height: m.height)
    img = white.cropped(to: r).composited(over: img)
}
white = white.cropped(to: .zero)

let ctx = CIContext()
guard let cg = ctx.createCGImage(img, from: CGRect(x: 0, y: 0, width: W, height: CH)),
      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError("render failed") }
try png.write(to: output)
print("wrote \(output.path)")
