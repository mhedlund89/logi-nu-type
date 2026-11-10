import SwiftUI

/// Three-quarter (front-left) mechanical drawing of the MX Master 2S with numbered callouts, inked like a mecha
/// design sheet: heavy silhouette, panel lines, faceted thumb rest, knurling, hatched shadow planes and small
/// handwritten notes. No branding is drawn.
///
/// The drawing lives in a fixed design space and is scaled at draw time (always sharp). `InteractiveSchematic`
/// uses the same static geometry for hit targets.
struct MouseSchematic: View {
    enum Part: CaseIterable { case wheel, wheelMode, thumbWheel, forward, back, gesture }
    struct Callout { let index: Int; let part: Part; let title: String; let value: String }
    /// `.side`: labels in a column right of the drawing (Settings). `.below`: two-column grid under it (menu panel).
    enum Layout { case side, below }

    let callouts: [Callout]
    let connected: Bool
    let p: WirePalette
    var selected: Int? = nil
    var layout: Layout = .side

    // MARK: Geometry (design space)

    static func designSize(_ l: Layout) -> CGSize { l == .side ? CGSize(width: 480, height: 236) : CGSize(width: 312, height: 302) }
    static func origin(_ l: Layout) -> CGPoint { l == .side ? CGPoint(x: 4, y: 22) : CGPoint(x: 6, y: 12) }
    static let labelX: CGFloat = 322

    // Side-control slot axis (drawing-local): back button at the low end, forward at the high end.
    private static let slotA = CGPoint(x: 152, y: 104), slotB = CGPoint(x: 214, y: 32)
    private static func onSlot(_ t: CGFloat) -> CGPoint {
        CGPoint(x: slotA.x + (slotB.x - slotA.x) * t, y: slotA.y + (slotB.y - slotA.y) * t)
    }

    /// Callout anchors in drawing-local coordinates.
    static let anchors: [Part: CGPoint] = [
        .wheel: CGPoint(x: 52, y: 104), .wheelMode: CGPoint(x: 100, y: 57), .thumbWheel: onSlot(0.46),
        .forward: onSlot(0.83), .back: onSlot(0.11), .gesture: CGPoint(x: 226, y: 92),
    ]

    private static let belowSlots: [Part: (col: Int, row: Int)] = [
        .wheel: (0, 0), .wheelMode: (0, 1), .back: (0, 2), .forward: (1, 0), .thumbWheel: (1, 1), .gesture: (1, 2),
    ]

    /// Top-left of the numbered box for a callout, in design space.
    static func boxOrigin(for c: Callout, in callouts: [Callout], layout l: Layout) -> CGPoint {
        switch l {
        case .side:
            // Rows ordered by anchor height so leaders cross as little as possible.
            let order = callouts.sorted { (anchors[$0.part]?.y ?? 0) < (anchors[$1.part]?.y ?? 0) }
            let row = order.firstIndex { $0.index == c.index } ?? 0
            let h = (designSize(l).height - 10) / CGFloat(max(callouts.count, 1))
            return CGPoint(x: labelX, y: 5 + h * (CGFloat(row) + 0.5) - 6)
        case .below:
            let slot = belowSlots[c.part] ?? (0, 0)
            return CGPoint(x: 22 + CGFloat(slot.col) * 150, y: 214 + CGFloat(slot.row) * 30)
        }
    }

    /// Clickable area for a callout's label, in design space.
    static func hitRect(for c: Callout, in callouts: [Callout], layout l: Layout) -> CGRect {
        let o = boxOrigin(for: c, in: callouts, layout: l)
        switch l {
        case .side:
            let h = (designSize(l).height - 10) / CGFloat(max(callouts.count, 1))
            return CGRect(x: o.x - 4, y: o.y + 6 - h / 2, width: designSize(l).width - o.x + 4, height: h)
        case .below:
            return CGRect(x: o.x - 2, y: o.y - 4, width: 140, height: 28)
        }
    }

    // MARK: Body

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let s = size.width / Self.designSize(layout).width
            ctx.scaleBy(x: s, y: s)
            drawMouse(&ctx)
            if layout == .side && s >= 0.95 { drawNotes(&ctx) }
            drawCallouts(&ctx)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mouse button layout: " + callouts.map { "\($0.title) \($0.value)" }.joined(separator: ", "))
    }

    // MARK: Helpers

    private var o: CGPoint { Self.origin(layout) }
    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x, y: o.y + y) }
    private func pt(_ q: CGPoint) -> CGPoint { pt(q.x, q.y) }

    /// Polygon with rounded corners.
    private func roundedPoly(_ pts: [CGPoint], r: CGFloat) -> Path {
        var path = Path()
        let n = pts.count
        let start = CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2)
        path.move(to: pt(start))
        for i in 0..<n { path.addArc(tangent1End: pt(pts[i]), tangent2End: pt(pts[(i + 1) % n]), radius: r) }
        path.closeSubpath()
        return path
    }

    /// Rounded rect centred on a drawing-local point, rotated by `deg`.
    private func rotatedRect(center c: CGPoint, w: CGFloat, h: CGFloat, r: CGFloat, deg: CGFloat) -> Path {
        let p = pt(c)
        return Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: r)
            .applying(CGAffineTransform(rotationAngle: deg * .pi / 180).concatenating(CGAffineTransform(translationX: p.x, y: p.y)))
    }

    private func hatch(_ ctx: inout GraphicsContext, clip: Path, spacing: CGFloat, angle: CGFloat, color: Color, width: CGFloat = 0.6) {
        ctx.drawLayer { layer in
            layer.clip(to: clip)
            let b = clip.boundingRect.insetBy(dx: -40, dy: -40)
            var lines = Path()
            var x = b.minX
            let dx = tan(angle * .pi / 180) * b.height
            while x < b.maxX + abs(dx) { lines.move(to: CGPoint(x: x, y: b.maxY)); lines.addLine(to: CGPoint(x: x - dx, y: b.minY)); x += spacing }
            layer.stroke(lines, with: .color(color), lineWidth: width)
        }
    }

    // MARK: Shapes (drawing-local)

    private var topShell: Path {
        var b = Path()
        b.move(to: pt(5, 134))
        b.addCurve(to: pt(48, 43), control1: pt(6, 108), control2: pt(24, 68))
        b.addCurve(to: pt(152, 3), control1: pt(75, 20), control2: pt(115, 6))
        b.addCurve(to: pt(217, 19), control1: pt(182, 1), control2: pt(204, 8))
        b.addCurve(to: pt(130, 112), control1: pt(195, 45), control2: pt(160, 80))
        b.addCurve(to: pt(72, 172), control1: pt(108, 135), control2: pt(86, 160))
        b.addCurve(to: pt(24, 162), control1: pt(55, 172), control2: pt(36, 168))
        b.addCurve(to: pt(5, 134), control1: pt(14, 155), control2: pt(7, 145))
        b.closeSubpath()
        return b
    }

    private var frontFace: Path {
        var f = Path()
        f.move(to: pt(5, 134))
        f.addCurve(to: pt(24, 162), control1: pt(7, 145), control2: pt(14, 155))
        f.addCurve(to: pt(72, 172), control1: pt(36, 168), control2: pt(55, 172))
        f.addLine(to: pt(78, 180))
        f.addCurve(to: pt(20, 170), control1: pt(58, 181), control2: pt(36, 178))
        f.addCurve(to: pt(5, 137), control1: pt(12, 163), control2: pt(8, 150))
        f.closeSubpath()
        return f
    }

    private var trimBand: Path {
        var t = Path()
        t.move(to: pt(217, 19))
        t.addCurve(to: pt(130, 112), control1: pt(195, 45), control2: pt(160, 80))
        t.addCurve(to: pt(72, 172), control1: pt(108, 135), control2: pt(86, 160))
        t.addLine(to: pt(79, 180))
        t.addCurve(to: pt(138, 116), control1: pt(93, 166), control2: pt(116, 139))
        t.addCurve(to: pt(226, 21), control1: pt(168, 84), control2: pt(204, 48))
        t.closeSubpath()
        return t
    }

    private var sideFrame: Path {
        var s = Path()
        s.move(to: pt(226, 21))
        s.addCurve(to: pt(262, 36), control1: pt(240, 22), control2: pt(252, 28))
        s.addCurve(to: pt(292, 100), control1: pt(276, 50), control2: pt(288, 76))
        s.addCurve(to: pt(291, 140), control1: pt(296, 116), control2: pt(295, 130))
        s.addCurve(to: pt(272, 153), control1: pt(288, 148), control2: pt(282, 152))
        s.addCurve(to: pt(160, 146), control1: pt(240, 153), control2: pt(195, 150))
        s.addCurve(to: pt(116, 140), control1: pt(140, 144), control2: pt(126, 142))
        s.addCurve(to: pt(138, 116), control1: pt(124, 132), control2: pt(131, 124))
        s.addCurve(to: pt(226, 21), control1: pt(168, 84), control2: pt(204, 48))
        s.closeSubpath()
        return s
    }

    private static let restCorners = [CGPoint(x: 184, y: 72), CGPoint(x: 258, y: 44), CGPoint(x: 282, y: 128), CGPoint(x: 172, y: 138)]
    private var thumbRest: Path { roundedPoly(Self.restCorners, r: 9) }

    private var underside: Path {
        var u = Path()
        u.move(to: pt(291, 140))
        u.addCurve(to: pt(272, 153), control1: pt(288, 148), control2: pt(282, 152))
        u.addCurve(to: pt(160, 146), control1: pt(240, 153), control2: pt(195, 150))
        u.addCurve(to: pt(116, 140), control1: pt(140, 144), control2: pt(126, 142))
        u.addCurve(to: pt(79, 180), control1: pt(104, 154), control2: pt(90, 168))
        u.addCurve(to: pt(200, 162), control1: pt(110, 176), control2: pt(160, 166))
        u.addCurve(to: pt(286, 150), control1: pt(240, 158), control2: pt(270, 155))
        u.closeSubpath()
        return u
    }

    // MARK: Mouse

    private func drawMouse(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(p.ink)
        let hair = GraphicsContext.Shading.color(p.hairline)

        // Body axis (construction line).
        var axis = Path()
        axis.move(to: pt(18, 176)); axis.addLine(to: pt(206, -6))
        ctx.stroke(axis, with: hair, style: StrokeStyle(lineWidth: 0.5, dash: [7, 2, 1.5, 2]))

        // Shadow planes first: underside (dense), front face (light).
        hatch(&ctx, clip: underside, spacing: 1.8, angle: 28, color: p.faint, width: 0.55)
        ctx.stroke(underside, with: ink, lineWidth: 1)
        hatch(&ctx, clip: frontFace, spacing: 2.6, angle: -20, color: p.hairline, width: 0.5)
        ctx.stroke(frontFace, with: ink, lineWidth: 1)

        // Thumb-side frame and faceted thumb rest (the rest is the gesture button: press it down).
        ctx.stroke(sideFrame, with: ink, lineWidth: 1.4)
        drawFacets(&ctx)
        ctx.stroke(thumbRest, with: ink, lineWidth: 1.1)
        ctx.stroke(roundedPoly(Self.restCorners.map { CGPoint(x: $0.x + ($0.x < 220 ? 3 : -3), y: $0.y + ($0.y < 100 ? 3 : -3)) }, r: 7),
                   with: hair, lineWidth: 0.5)

        // Trim band with a sheen line.
        ctx.stroke(trimBand, with: ink, lineWidth: 1)
        var sheen = Path()
        sheen.move(to: pt(221, 21)); sheen.addCurve(to: pt(134, 114), control1: pt(199, 47), control2: pt(164, 82))
        sheen.addCurve(to: pt(75, 176), control1: pt(112, 137), control2: pt(89, 163))
        ctx.stroke(sheen, with: hair, lineWidth: 0.5)

        // Battery LEDs on the trim, by the thumb rest.
        for (i, q) in [CGPoint(x: 120, y: 145), CGPoint(x: 125, y: 144.5), CGPoint(x: 130, y: 144)].enumerated() {
            let c = CGRect(x: o.x + q.x - 1.3, y: o.y + q.y - 1.3, width: 2.6, height: 2.6)
            if connected && i == 0 { ctx.fill(Path(ellipseIn: c), with: ink) }
            ctx.stroke(Path(ellipseIn: c), with: ink, lineWidth: 0.6)
        }

        // Top shell (inked heavy) and its secondary contours.
        ctx.stroke(topShell, with: ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        var form = Path()
        form.move(to: pt(13, 128)); form.addCurve(to: pt(150, 9), control1: pt(16, 80), control2: pt(70, 22))
        ctx.stroke(form, with: hair, lineWidth: 0.5)
        var shoulder = Path()
        shoulder.move(to: pt(196, 22)); shoulder.addCurve(to: pt(122, 112), control1: pt(178, 46), control2: pt(146, 82))
        ctx.stroke(shoulder, with: hair, style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))

        // Button seam: from the crown down to the wheel slot, then on to the nose.
        var seam = Path()
        seam.move(to: pt(86, 22)); seam.addCurve(to: pt(63, 90), control1: pt(78, 45), control2: pt(68, 70))
        seam.move(to: pt(58, 122)); seam.addCurve(to: pt(60, 170), control1: pt(56, 140), control2: pt(57, 156))
        ctx.stroke(seam, with: ink, lineWidth: 0.9)

        // Palm plate (blank — no logo).
        let plate = roundedPoly([CGPoint(x: 110, y: 60), CGPoint(x: 163, y: 46), CGPoint(x: 126, y: 104), CGPoint(x: 86, y: 116)], r: 5)
        ctx.stroke(plate, with: ink, lineWidth: 0.9)
        hatch(&ctx, clip: plate, spacing: 5, angle: 55, color: p.hairline, width: 0.4)

        // Wheel-mode button.
        ctx.stroke(rotatedRect(center: CGPoint(x: 100, y: 57), w: 13, h: 10, r: 2.5, deg: -22), with: ink, lineWidth: 1)
        ctx.stroke(rotatedRect(center: CGPoint(x: 100, y: 57), w: 8, h: 5, r: 1.2, deg: -22), with: hair, lineWidth: 0.5)

        drawWheel(&ctx)
        drawSideControls(&ctx)

        // Charging port on the front face.
        ctx.stroke(rotatedRect(center: CGPoint(x: 42, y: 173), w: 10, h: 3.6, r: 1.2, deg: 9), with: ink, lineWidth: 0.8)
    }

    private func drawFacets(_ ctx: inout GraphicsContext) {
        let c = Self.restCorners
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        func at(_ u: CGFloat, _ v: CGFloat) -> CGPoint { lerp(lerp(c[0], c[1], u), lerp(c[3], c[2], u), v) }
        let cols = 5, rows = 4
        var grid: [[CGPoint]] = []
        for j in 0...rows {
            var row: [CGPoint] = []
            for i in 0...cols {
                var u = CGFloat(i) / CGFloat(cols), v = CGFloat(j) / CGFloat(rows)
                if i > 0 && i < cols && j > 0 && j < rows {   // deterministic jitter for a low-poly look
                    u += 0.07 * sin(CGFloat(i * 12 + j * 7)); v += 0.08 * cos(CGFloat(i * 5 + j * 11))
                }
                row.append(at(u, v))
            }
            grid.append(row)
        }
        var lines = Path()
        for j in 0..<rows {
            for i in 0..<cols {
                let a = grid[j][i], b = grid[j][i + 1], d = grid[j + 1][i], e = grid[j + 1][i + 1]
                lines.move(to: pt(a)); lines.addLine(to: pt(b)); lines.addLine(to: pt(e)); lines.addLine(to: pt(d)); lines.closeSubpath()
                lines.move(to: pt((i + j) % 2 == 0 ? a : b)); lines.addLine(to: pt((i + j) % 2 == 0 ? e : d))
            }
        }
        let rest = thumbRest
        ctx.drawLayer { layer in
            layer.clip(to: rest)
            layer.stroke(lines, with: .color(p.hairline), lineWidth: 0.55)
            // Shade a few facets, like the darker planes in the photo.
            for (i, j) in [(1, 1), (3, 2), (2, 3), (4, 0)] {
                var tri = Path()
                tri.move(to: pt(grid[j][i])); tri.addLine(to: pt(grid[j][i + 1])); tri.addLine(to: pt(grid[j + 1][i + 1])); tri.closeSubpath()
                layer.drawLayer { l in
                    l.clip(to: tri)
                    var h = Path()
                    let b = tri.boundingRect
                    var x = b.minX - b.height
                    while x < b.maxX { h.move(to: CGPoint(x: x, y: b.maxY)); h.addLine(to: CGPoint(x: x + b.height, y: b.minY)); x += 2.2 }
                    l.stroke(h, with: .color(p.hairline), lineWidth: 0.5)
                }
            }
        }
    }

    private func drawWheel(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(p.ink)
        let hair = GraphicsContext.Shading.color(p.hairline)
        let centre = pt(56, 106)
        ctx.drawLayer { layer in
            layer.translateBy(x: centre.x, y: centre.y)
            layer.rotate(by: .degrees(-24))
            // Recessed slot, hatched dark.
            let slot = Path(roundedRect: CGRect(x: -24, y: -16, width: 48, height: 32), cornerRadius: 9)
            layer.drawLayer { l in
                l.clip(to: slot)
                var h = Path()
                var x: CGFloat = -60
                while x < 60 { h.move(to: CGPoint(x: x, y: 20)); h.addLine(to: CGPoint(x: x + 18, y: -20)); x += 1.8 }
                l.stroke(h, with: .color(p.faint), lineWidth: 0.5)
            }
            layer.stroke(slot, with: ink, lineWidth: 1.2)
            layer.stroke(Path(roundedRect: CGRect(x: -21, y: -13, width: 42, height: 26), cornerRadius: 7), with: hair, lineWidth: 0.5)
            // Chrome face: the disc's flat side, with turned-metal rings.
            var face = Path()
            face.move(to: CGPoint(x: -14, y: 2))
            face.addCurve(to: CGPoint(x: 14, y: 2), control1: CGPoint(x: -13, y: 13), control2: CGPoint(x: 13, y: 13))
            face.closeSubpath()
            layer.fill(face, with: .color(p.paper))
            layer.stroke(face, with: ink, lineWidth: 0.9)
            for k: CGFloat in [3.5, 7] {
                var ring = Path()
                ring.move(to: CGPoint(x: -14 + k, y: 2)); ring.addCurve(to: CGPoint(x: 14 - k, y: 2),
                    control1: CGPoint(x: -13 + k, y: 13 - k), control2: CGPoint(x: 13 - k, y: 13 - k))
                layer.stroke(ring, with: hair, lineWidth: 0.5)
            }
            // Knurled rim: a crescent seen from above, with radial knurl lines.
            func bez(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
                let u = 1 - t
                return CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p3.x,
                               y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p3.y)
            }
            let o0 = CGPoint(x: -18, y: 2), o1 = CGPoint(x: -18, y: -13), o2 = CGPoint(x: 18, y: -13), o3 = CGPoint(x: 18, y: 2)
            let i0 = CGPoint(x: -14, y: 2), i1 = CGPoint(x: -14, y: -8), i2 = CGPoint(x: 14, y: -8), i3 = CGPoint(x: 14, y: 2)
            var rim = Path()
            rim.move(to: o0); rim.addCurve(to: o3, control1: o1, control2: o2)
            rim.addLine(to: i3); rim.addCurve(to: i0, control1: i2, control2: i1)
            rim.closeSubpath()
            layer.fill(rim, with: .color(p.paper))
            var knurl = Path()
            for n in 1..<22 {
                let t = CGFloat(n) / 22
                knurl.move(to: bez(i0, i1, i2, i3, t)); knurl.addLine(to: bez(o0, o1, o2, o3, min(1, t + 0.025)))
            }
            layer.stroke(knurl, with: ink, lineWidth: 0.55)
            layer.stroke(rim, with: ink, lineWidth: 1)
            // Axle stubs at the slot walls.
            var axle = Path()
            axle.move(to: CGPoint(x: -24, y: 2)); axle.addLine(to: CGPoint(x: -18, y: 2))
            axle.move(to: CGPoint(x: 18, y: 2)); axle.addLine(to: CGPoint(x: 24, y: 2))
            layer.stroke(axle, with: ink, lineWidth: 0.8)
        }
    }

    private func drawSideControls(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(p.ink)
        let hair = GraphicsContext.Shading.color(p.hairline)
        let a = pt(Self.slotA), b = pt(Self.slotB)
        let len = hypot(b.x - a.x, b.y - a.y)
        let angle = atan2(b.y - a.y, b.x - a.x)
        ctx.drawLayer { layer in
            layer.translateBy(x: a.x, y: a.y)
            layer.rotate(by: .radians(angle))
            // Recess along the side wall.
            let slot = Path(roundedRect: CGRect(x: -4, y: -7.5, width: len + 8, height: 15), cornerRadius: 7.5)
            layer.drawLayer { l in
                l.clip(to: slot)
                var h = Path()
                var x: CGFloat = -10
                while x < len + 10 { h.move(to: CGPoint(x: x, y: 8)); h.addLine(to: CGPoint(x: x + 6, y: -8)); x += 1.9 }
                l.stroke(h, with: .color(p.faint), lineWidth: 0.45)
            }
            layer.stroke(slot, with: ink, lineWidth: 1)
            // Back button (low end), forward button (high end).
            for r in [CGRect(x: 0, y: -5, width: len * 0.22, height: 10), CGRect(x: len * 0.72, y: -4, width: len * 0.24, height: 8)] {
                let btn = Path(roundedRect: r, cornerRadius: r.height / 2)
                layer.fill(btn, with: .color(p.paper))
                layer.stroke(btn, with: ink, lineWidth: 1)
                var ridge = Path()
                ridge.move(to: CGPoint(x: r.minX + 3, y: r.midY - 1.5)); ridge.addLine(to: CGPoint(x: r.maxX - 3, y: r.midY - 1.5))
                layer.stroke(ridge, with: hair, lineWidth: 0.5)
            }
            // Thumb wheel: ringed cylinder with chrome end caps.
            let cyl = CGRect(x: len * 0.3, y: -6.5, width: len * 0.33, height: 13)
            let body = Path(roundedRect: cyl, cornerRadius: 2.5)
            layer.fill(body, with: .color(p.paper))
            layer.drawLayer { l in
                l.clip(to: body)
                var rings = Path()
                var x = cyl.minX + 3
                while x < cyl.maxX - 2 { rings.move(to: CGPoint(x: x, y: cyl.minY)); rings.addLine(to: CGPoint(x: x, y: cyl.maxY)); x += 2.1 }
                l.stroke(rings, with: ink, lineWidth: 0.55)
            }
            layer.stroke(body, with: ink, lineWidth: 1.1)
            for x in [cyl.minX, cyl.maxX] {
                let cap = Path(ellipseIn: CGRect(x: x - 1.8, y: cyl.minY + 0.5, width: 3.6, height: cyl.height - 1))
                layer.fill(cap, with: .color(p.paper))
                layer.stroke(cap, with: ink, lineWidth: 0.8)
            }
        }
    }

    // MARK: Notes

    private func drawNotes(_ ctx: inout GraphicsContext) {
        let faint = GraphicsContext.Shading.color(p.faint)
        let font = Font.system(size: 5.4, weight: .regular, design: .serif)
        func note(_ text: String, at: CGPoint, from: CGPoint, anchor: UnitPoint) {
            let a = pt(at), f = pt(from)
            if a != f {
                var l = Path(); l.move(to: f); l.addLine(to: a)
                ctx.stroke(l, with: faint, lineWidth: 0.4)
            }
            let resolved = ctx.resolve(Text(text).font(font).foregroundColor(p.faint))
            let sz = resolved.measure(in: CGSize(width: 200, height: 20))
            let box = CGRect(x: a.x - anchor.x * sz.width, y: a.y - anchor.y * sz.height, width: sz.width, height: sz.height)
            ctx.fill(Path(box.insetBy(dx: -1.5, dy: -0.5)), with: .color(p.paper))
            ctx.draw(resolved, at: a, anchor: anchor)
        }
        note("メタルホイール", at: CGPoint(x: 2, y: 30), from: CGPoint(x: 44, y: 98), anchor: .leading)
        note("モードシフト", at: CGPoint(x: 40, y: 2), from: CGPoint(x: 97, y: 54), anchor: .leading)
        note("サムホイール", at: CGPoint(x: 232, y: 6), from: CGPoint(x: 184, y: 66), anchor: .leading)
        note("ジェスチャー (押下)", at: CGPoint(x: 236, y: 172), from: CGPoint(x: 232, y: 118), anchor: .leading)
        note("電池残量LED ×3", at: CGPoint(x: 110, y: 196), from: CGPoint(x: 125, y: 147), anchor: .leading)
        note("充電端子", at: CGPoint(x: 6, y: 192), from: CGPoint(x: 40, y: 175), anchor: .leading)
        note("3/4 前左面図", at: CGPoint(x: 300, y: 196), from: CGPoint(x: 300, y: 196), anchor: .trailing)
    }

    // MARK: Callouts

    private func drawCallouts(_ ctx: inout GraphicsContext) {
        let ink = GraphicsContext.Shading.color(p.ink)
        for c in callouts {
            guard let a = Self.anchors[c.part] else { continue }
            let anchor = pt(a)
            let box0 = Self.boxOrigin(for: c, in: callouts, layout: layout)
            let box = CGRect(x: box0.x, y: box0.y, width: 12, height: 12)
            let isSelected = c.index == selected
            var leader = Path()
            leader.move(to: anchor)
            switch layout {
            case .side:
                leader.addLine(to: CGPoint(x: box.minX - 18, y: box.midY))
                leader.addLine(to: CGPoint(x: box.minX - 4, y: box.midY))
            case .below:
                // Down a staggered gutter left of the column, then in to the box: never crosses other labels.
                let row = CGFloat(Int((box0.y - 214) / 30))
                let gutter = box.minX - 5 - row * 4
                leader.addLine(to: CGPoint(x: gutter, y: 204))
                leader.addLine(to: CGPoint(x: gutter, y: box.midY))
                leader.addLine(to: CGPoint(x: box.minX - 1, y: box.midY))
            }
            ctx.stroke(leader, with: .color(p.ink.opacity(connected ? (isSelected ? 1 : 0.75) : 0.3)),
                       lineWidth: isSelected ? 1.1 : 0.6)
            ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - 1.8, y: anchor.y - 1.8, width: 3.6, height: 3.6)), with: ink)
            if isSelected {
                ctx.stroke(Path(ellipseIn: CGRect(x: anchor.x - 5, y: anchor.y - 5, width: 10, height: 10)), with: ink, lineWidth: 1)
                ctx.fill(Path(box), with: ink)
            } else {
                ctx.stroke(Path(box), with: ink, lineWidth: 0.9)
            }
            ctx.draw(Text("\(c.index)").font(WireFont.label(8, .bold)).foregroundColor(isSelected ? p.paper : p.ink),
                     at: CGPoint(x: box.midX, y: box.midY))
            ctx.draw(Text(c.title).font(WireFont.label(7)).foregroundColor(p.faint),
                     at: CGPoint(x: box.maxX + 5, y: box.midY - 5), anchor: .leading)
            ctx.draw(Text(c.value).font(WireFont.label(layout == .side ? 9 : 7.5, .semibold)).foregroundColor(p.ink),
                     at: CGPoint(x: box.maxX + 5, y: box.midY + 5), anchor: .leading)
        }
        if !connected {
            ctx.draw(Text("— UNIT NOT CONNECTED —").font(WireFont.label(8, .bold)).foregroundColor(p.faint),
                     at: pt(150, 200))
        }
    }
}
