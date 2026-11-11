import AppKit

/// The menu bar mark: "NU" as chamfered armour blocks with panel-line seams, after the app icon.
/// A template image, so macOS tints it for light/dark menu bars and the highlighted state.
enum NUMark {
    /// Design grid is 25 × 16 units (y up); drawn at `height` points.
    static func image(height: CGFloat = 15) -> NSImage {
        let s = height / 16
        let img = NSImage(size: NSSize(width: 25 * s, height: height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: s, y: s)
            func poly(_ pts: [(CGFloat, CGFloat)]) -> CGPath {
                let p = CGMutablePath()
                p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
                p.closeSubpath()
                return p
            }
            // N: left stem, diagonal, right stem; chamfered top-left and bottom-right corners.
            let n = poly([(0, 0), (0, 14.6), (1.4, 16), (4.2, 16), (8.2, 7.4), (8.2, 16), (11.4, 16), (11.4, 1.4),
                          (10, 0), (7.2, 0), (3.2, 8.6), (3.2, 0)])
            // U: two stems joined by a chamfered bowl.
            let u = poly([(13.6, 16), (13.6, 4.2), (17.8, 0), (20.8, 0), (25, 4.2), (25, 16), (21.8, 16), (21.8, 5.4),
                          (20.2, 3.6), (18.4, 3.6), (16.8, 5.4), (16.8, 16)])
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(n); ctx.addPath(u); ctx.fillPath()
            // Panel seams cut through the plates.
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(0.9)
            ctx.setLineCap(.butt)
            for (a, b) in [((0.0, 5.0), (3.2, 5.0)),          // N left stem
                           ((8.2, 9.6), (11.4, 11.0)),        // N right stem
                           ((13.6, 9.0), (16.8, 9.0)),        // U left stem
                           ((21.8, 2.6), (25.0, 6.4))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
                ctx.move(to: CGPoint(x: a.0, y: a.1)); ctx.addLine(to: CGPoint(x: b.0, y: b.1))
            }
            ctx.strokePath()
            // Rivet holes.
            for (x, y) in [(1.6, 13.4), (9.8, 13.4), (15.2, 13.4), (23.4, 13.4)] as [(CGFloat, CGFloat)] {
                ctx.fillEllipse(in: CGRect(x: x - 0.55, y: y - 0.55, width: 1.1, height: 1.1))
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Logi : nu-type"
        return img
    }
}
