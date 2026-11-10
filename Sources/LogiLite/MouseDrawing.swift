import SwiftUI

/// Top-view mechanical drawing of the MX Master 2S with numbered callouts, in the style of a hand-inked
/// mecha design sheet: inked contour, hairline secondary contours, knurling, grip texture, a centre line,
/// section marker, dimension line and small handwritten notes.
///
/// Everything is laid out in a fixed design space (`designSize`) and scaled at draw time, so the drawing stays
/// sharp at any size. `InteractiveSchematic` uses the same static geometry for its hit targets.
struct MouseSchematic: View {
    enum Part { case wheel, wheelMode, thumbWheel, forward, back, gesture }
    struct Callout { let index: Int; let part: Part; let title: String; let value: String }

    let callouts: [Callout]
    let connected: Bool
    let p: WirePalette
    var selected: Int? = nil

    // MARK: Geometry (design space)

    static let designSize = CGSize(width: 360, height: 236)
    /// Top-left of the mouse's 140 × 212 drawing box.
    static let origin = CGPoint(x: 10, y: 12)
    static let labelX: CGFloat = 178

    /// Callout anchor points in mouse-local coordinates.
    static let anchors: [Part: CGPoint] = [
        .wheel: CGPoint(x: 76, y: 44), .wheelMode: CGPoint(x: 76, y: 78), .thumbWheel: CGPoint(x: 24, y: 86),
        .forward: CGPoint(x: 25, y: 106), .back: CGPoint(x: 26, y: 118), .gesture: CGPoint(x: 20, y: 141),
    ]

    static func rowY(_ i: Int, of count: Int) -> CGFloat {
        let h = (designSize.height - 10) / CGFloat(max(count, 1))
        return 5 + h * (CGFloat(i) + 0.5)
    }
    static func rowHeight(of count: Int) -> CGFloat { (designSize.height - 10) / CGFloat(max(count, 1)) }

    // MARK: Body

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let s = size.width / Self.designSize.width
            ctx.scaleBy(x: s, y: s)
            drawMouse(&ctx, scale: s)
            drawCallouts(&ctx)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mouse button layout: " + callouts.map { "\($0.title) \($0.value)" }.joined(separator: ", "))
    }

    // MARK: Drawing

    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: Self.origin.x + x, y: Self.origin.y + y) }
    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: Self.origin.x + x, y: Self.origin.y + y, width: w, height: h)
    }

    /// Outer silhouette: long sculpted body, flat-ish right flank, thumb ledge flaring out bottom-left.
    private var outline: Path {
        var b = Path()
        b.move(to: pt(58, 6))
        b.addCurve(to: pt(96, 4), control1: pt(66, 1), control2: pt(86, 0))          // front edge
        b.addCurve(to: pt(124, 44), control1: pt(110, 8), control2: pt(121, 24))     // front-right shoulder
        b.addCurve(to: pt(128, 108), control1: pt(128, 64), control2: pt(130, 86))   // right flank
        b.addCurve(to: pt(112, 178), control1: pt(126, 136), control2: pt(122, 160)) // right rear
        b.addCurve(to: pt(74, 210), control1: pt(102, 196), control2: pt(90, 208))   // rear
        b.addCurve(to: pt(36, 200), control1: pt(58, 212), control2: pt(46, 208))    // rear-left
        b.addCurve(to: pt(7, 166), control1: pt(22, 192), control2: pt(9, 182))      // thumb ledge flare
        b.addCurve(to: pt(11, 132), control1: pt(5, 152), control2: pt(5, 140))      // ledge outer edge
        b.addCurve(to: pt(25, 122), control1: pt(15, 127), control2: pt(20, 125))    // step up to side wall
        b.addCurve(to: pt(26, 70), control1: pt(30, 104), control2: pt(24, 86))      // side wall
        b.addCurve(to: pt(58, 6), control1: pt(28, 40), control2: pt(40, 12))        // front-left shoulder
        b.closeSubpath()
        return b
    }

    /// Boundary between the side wall and the thumb ledge.
    private var ledgeEdge: Path {
        var e = Path()
        e.move(to: pt(25, 122))
        e.addCurve(to: pt(52, 205), control1: pt(30, 150), control2: pt(38, 182))
        return e
    }

    private func drawMouse(_ ctx: inout GraphicsContext, scale: CGFloat) {
        let ink = GraphicsContext.Shading.color(p.ink)
        let hair = GraphicsContext.Shading.color(p.hairline)
        let faint = GraphicsContext.Shading.color(p.faint)
        let body = outline

        // Construction lines: centre line, section A–A, dimension.
        var centre = Path()
        centre.move(to: pt(76, -8)); centre.addLine(to: pt(76, 216))
        ctx.stroke(centre, with: hair, style: StrokeStyle(lineWidth: 0.6, dash: [7, 2, 1.5, 2]))
        var section = Path()
        section.move(to: pt(-4, 156)); section.addLine(to: pt(136, 156))
        ctx.stroke(section, with: hair, style: StrokeStyle(lineWidth: 0.6, dash: [7, 2, 1.5, 2]))
        for x: CGFloat in [-4, 136] {
            var tri = Path()
            tri.move(to: pt(x, 152)); tri.addLine(to: pt(x, 160)); tri.addLine(to: pt(x + (x < 0 ? 4 : -4), 156)); tri.closeSubpath()
            ctx.fill(tri, with: faint)
            ctx.draw(Text("A").font(.system(size: 6, weight: .bold, design: .serif)).foregroundColor(p.faint),
                     at: pt(x, 147))
        }
        var dim = Path()
        dim.move(to: pt(7, 220)); dim.addLine(to: pt(128, 220))
        for (x, d) in [(CGFloat(7), CGFloat(1)), (CGFloat(128), CGFloat(-1))] {
            dim.move(to: pt(x, 215)); dim.addLine(to: pt(x, 223))
            dim.move(to: pt(x + 4 * d, 218.5)); dim.addLine(to: pt(x, 220)); dim.addLine(to: pt(x + 4 * d, 221.5))
        }
        ctx.stroke(dim, with: faint, lineWidth: 0.6)
        ctx.draw(Text("85.7").font(.system(size: 6, design: .monospaced)).foregroundColor(p.faint), at: pt(67, 216))

        // Shadow side: hatch along the right rear flank, like inked shading.
        ctx.drawLayer { layer in
            var band = Path()
            band.move(to: pt(128, 108)); band.addCurve(to: pt(112, 178), control1: pt(126, 136), control2: pt(122, 160))
            band.addCurve(to: pt(74, 210), control1: pt(102, 196), control2: pt(90, 208))
            band.addLine(to: pt(74, 202))
            band.addCurve(to: pt(106, 172), control1: pt(88, 200), control2: pt(98, 188))
            band.addCurve(to: pt(120, 108), control1: pt(116, 154), control2: pt(119, 132))
            band.closeSubpath()
            layer.clip(to: band)
            var hatch = Path()
            var x: CGFloat = 60
            while x < 140 { hatch.move(to: pt(x, 100)); hatch.addLine(to: pt(x - 40, 215)); x += 2.6 }
            layer.stroke(hatch, with: hair, lineWidth: 0.7)
        }

        // Thumb ledge grip texture (dot matrix), clipped to the ledge.
        ctx.drawLayer { layer in
            var ledge = Path()
            ledge.move(to: pt(25, 122))
            ledge.addCurve(to: pt(52, 205), control1: pt(30, 150), control2: pt(38, 182))
            ledge.addCurve(to: pt(36, 200), control1: pt(46, 207), control2: pt(40, 204))
            ledge.addCurve(to: pt(7, 166), control1: pt(22, 192), control2: pt(9, 182))
            ledge.addCurve(to: pt(11, 132), control1: pt(5, 152), control2: pt(5, 140))
            ledge.closeSubpath()
            layer.clip(to: ledge)
            var y: CGFloat = 150, row = 0
            while y < 210 {
                var x: CGFloat = (row % 2 == 0) ? 6 : 8
                while x < 50 { layer.fill(Path(ellipseIn: CGRect(x: Self.origin.x + x, y: Self.origin.y + y, width: 1.1, height: 1.1)), with: faint); x += 4 }
                y += 3.4; row += 1
            }
        }

        // Main contour, inked heavy; inner shell hairline.
        ctx.stroke(body, with: ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        let inner = body.applying(CGAffineTransform(translationX: Self.origin.x + 72, y: Self.origin.y + 104)
            .scaledBy(x: 0.92, y: 0.94).translatedBy(x: -(Self.origin.x + 72), y: -(Self.origin.y + 104)))
        ctx.stroke(inner, with: hair, lineWidth: 0.6)
        ctx.stroke(ledgeEdge, with: ink, lineWidth: 1)

        // Front lip and charging port.
        var lip = Path()
        lip.move(to: pt(60, 9)); lip.addCurve(to: pt(95, 8), control1: pt(68, 5), control2: pt(86, 4))
        ctx.stroke(lip, with: hair, lineWidth: 0.6)
        let port = rect(71, 0.5, 10, 4)
        ctx.stroke(Path(roundedRect: port, cornerRadius: 1.2), with: ink, lineWidth: 0.8)
        ctx.stroke(Path(roundedRect: port.insetBy(dx: 2, dy: 1.2), cornerRadius: 0.5), with: faint, lineWidth: 0.5)

        // Button split: centre seam from the nose to the wheel slot, and the rear seam of both buttons.
        var seams = Path()
        seams.move(to: pt(76, 4.5)); seams.addLine(to: pt(76, 22))
        seams.move(to: pt(27, 86)); seams.addCurve(to: pt(127, 80), control1: pt(60, 100), control2: pt(100, 98))
        ctx.stroke(seams, with: ink, lineWidth: 0.9)

        // Palm hump: topographic contour lines.
        for (i, k) in [CGFloat(0), 1, 2].enumerated() {
            var c = Path()
            c.move(to: pt(44 + k * 8, 132 + k * 6))
            c.addCurve(to: pt(112 - k * 8, 130 + k * 6), control1: pt(60 + k * 6, 112 + k * 8), control2: pt(96 - k * 6, 110 + k * 8))
            ctx.stroke(c, with: hair, style: StrokeStyle(lineWidth: 0.6, dash: i == 0 ? [] : [2, 1.5]))
        }

        // Wheel slot and steel wheel with knurling.
        let slot = rect(67, 22, 18, 48)
        ctx.stroke(Path(roundedRect: slot, cornerRadius: 8), with: ink, lineWidth: 1.1)
        let wheel = rect(70, 25, 12, 42)
        ctx.drawLayer { layer in
            let wp = Path(roundedRect: wheel, cornerRadius: 5.5)
            layer.clip(to: wp)
            var ribs = Path()
            var y = wheel.minY + 1.5
            while y < wheel.maxY { ribs.move(to: CGPoint(x: wheel.minX, y: y)); ribs.addLine(to: CGPoint(x: wheel.maxX, y: y)); y += 2.1 }
            layer.stroke(ribs, with: ink, lineWidth: 0.55)
            var knurl = Path()
            var x = wheel.minX - wheel.height
            while x < wheel.maxX { knurl.move(to: CGPoint(x: x, y: wheel.maxY)); knurl.addLine(to: CGPoint(x: x + wheel.height * 0.35, y: wheel.minY)); x += 3 }
            layer.stroke(knurl, with: hair, lineWidth: 0.5)
            // Highlight: leave a clean band down the middle of the steel.
            layer.fill(Path(CGRect(x: wheel.midX - 0.8, y: wheel.minY, width: 1.6, height: wheel.height)), with: .color(p.paper))
        }
        ctx.stroke(Path(roundedRect: wheel, cornerRadius: 5.5), with: ink, lineWidth: 1)
        var axle = Path()
        axle.move(to: pt(64, 46)); axle.addLine(to: pt(67, 46))
        axle.move(to: pt(85, 46)); axle.addLine(to: pt(88, 46))
        ctx.stroke(axle, with: ink, lineWidth: 0.8)

        // Wheel-mode button behind the wheel.
        let wm = rect(70, 74, 12, 9)
        ctx.stroke(Path(roundedRect: wm, cornerRadius: 2.5), with: ink, lineWidth: 1)
        ctx.stroke(Path(roundedRect: wm.insetBy(dx: 2, dy: 2), cornerRadius: 1), with: hair, lineWidth: 0.5)

        // Side wall: thumb wheel (housing + ribbed wheel), forward and back buttons.
        ctx.stroke(Path(roundedRect: rect(18, 70, 13, 32), cornerRadius: 5), with: hair, lineWidth: 0.6)
        let tw = rect(20, 73, 9, 26)
        ctx.drawLayer { layer in
            layer.clip(to: Path(roundedRect: tw, cornerRadius: 4))
            var r = Path()
            var y = tw.minY + 1.5
            while y < tw.maxY { r.move(to: CGPoint(x: tw.minX, y: y)); r.addLine(to: CGPoint(x: tw.maxX, y: y)); y += 2.2 }
            layer.stroke(r, with: ink, lineWidth: 0.5)
        }
        ctx.stroke(Path(roundedRect: tw, cornerRadius: 4), with: ink, lineWidth: 1)
        for (y, w) in [(CGFloat(101), CGFloat(10)), (CGFloat(113), CGFloat(10))] {
            let b = rect(21, y, w, 10)
            ctx.stroke(Path(roundedRect: b, cornerRadius: 2.5), with: ink, lineWidth: 1)
            var ridge = Path()
            ridge.move(to: CGPoint(x: b.minX + 2.5, y: b.midY)); ridge.addLine(to: CGPoint(x: b.maxX - 2.5, y: b.midY))
            ctx.stroke(ridge, with: hair, lineWidth: 0.5)
        }

        // Gesture button: the front lip of the thumb ledge, pressed down by the thumb.
        var gesture = Path()
        gesture.move(to: pt(11, 133))
        gesture.addQuadCurve(to: pt(30, 138), control: pt(20, 129))
        gesture.addQuadCurve(to: pt(13, 151), control: pt(29, 152))
        gesture.addQuadCurve(to: pt(11, 133), control: pt(8, 142))
        ctx.stroke(gesture, with: ink, lineWidth: 1)

        // Battery LEDs on the ledge edge.
        for (i, y) in [CGFloat(126), 131, 136].enumerated() {
            let c = rect(30 + CGFloat(i) * 1.2, y, 2.4, 2.4)
            ctx.fill(Path(ellipseIn: c), with: i == 0 && connected ? ink : .color(.clear))
            ctx.stroke(Path(ellipseIn: c), with: ink, lineWidth: 0.5)
        }

        // Handwritten notes (only where the drawing is big enough to read them).
        guard scale >= 1.2 else { return }
        let noteFont = Font.system(size: 5.2, weight: .regular, design: .serif)
        func note(_ text: String, at: CGPoint, from: CGPoint, anchor: UnitPoint) {
            var l = Path(); l.move(to: from); l.addLine(to: at)
            ctx.stroke(l, with: faint, lineWidth: 0.4)
            // Knock out a paper-coloured gap behind the note so lines never run through the lettering.
            let resolved = ctx.resolve(Text(text).font(noteFont).foregroundColor(p.faint))
            let sz = resolved.measure(in: CGSize(width: 200, height: 20))
            let box = CGRect(x: at.x - anchor.x * sz.width, y: at.y - anchor.y * sz.height, width: sz.width, height: sz.height)
            ctx.fill(Path(box.insetBy(dx: -1.5, dy: -0.5)), with: .color(p.paper))
            ctx.draw(resolved, at: at, anchor: anchor)
        }
        note("充電端子 (前面)", at: pt(52, -7), from: pt(72, 1), anchor: .trailing)
        note("金属ホイール ローレット加工", at: pt(92, -7), from: pt(83, 28), anchor: .leading)
        note("電池残量LED ×3", at: pt(44, 124), from: pt(34, 129), anchor: .leading)
        note("サムレスト 滑り止め", at: pt(-2, 213), from: pt(18, 188), anchor: .leading)
        note("パームレスト 曲面", at: pt(48, 174), from: pt(70, 146), anchor: .leading)
    }

    private func drawCallouts(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(p.ink)
        let lx = Self.labelX
        for (i, c) in callouts.enumerated() {
            guard let a = Self.anchors[c.part] else { continue }
            let anchor = pt(a.x, a.y)
            let ly = Self.rowY(i, of: callouts.count)
            let isSelected = c.index == selected
            var leader = Path()
            leader.move(to: anchor)
            leader.addLine(to: CGPoint(x: lx - 18, y: ly))
            leader.addLine(to: CGPoint(x: lx - 4, y: ly))
            ctx.stroke(leader, with: .color(p.ink.opacity(connected ? (isSelected ? 1 : 0.75) : 0.3)),
                       lineWidth: isSelected ? 1.1 : 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - 1.8, y: anchor.y - 1.8, width: 3.6, height: 3.6)), with: ink)
            if isSelected {
                ctx.stroke(Path(ellipseIn: CGRect(x: anchor.x - 5, y: anchor.y - 5, width: 10, height: 10)), with: ink, lineWidth: 1)
            }

            let box = CGRect(x: lx, y: ly - 6, width: 12, height: 12)
            if isSelected { ctx.fill(Path(box), with: ink) } else { ctx.stroke(Path(box), with: ink, lineWidth: 0.9) }
            ctx.draw(Text("\(c.index)").font(WireFont.label(8, .bold)).foregroundColor(isSelected ? p.paper : p.ink),
                     at: CGPoint(x: box.midX, y: box.midY))
            ctx.draw(Text(c.title).font(WireFont.label(7)).foregroundColor(p.faint),
                     at: CGPoint(x: lx + 17, y: ly - 5), anchor: .leading)
            ctx.draw(Text(c.value).font(WireFont.label(9, .semibold)).foregroundColor(p.ink),
                     at: CGPoint(x: lx + 17, y: ly + 5), anchor: .leading)
        }
        if !connected {
            ctx.draw(Text("— UNIT NOT CONNECTED —").font(WireFont.label(8, .bold)).foregroundColor(p.faint),
                     at: pt(68, 228))
        }
    }
}
