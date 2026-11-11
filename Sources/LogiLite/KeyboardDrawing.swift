import SwiftUI

/// Vector line drawing of the MX Keys Mac (top view), in the style of the reference sheet: double-outlined
/// keycaps, the raised "logi" strip with its status light, and dash-dot centre lines. Resolution independent.
struct KeyboardDrawing: View {
    let p: WirePalette

    /// Design units: 1 key = `u` points. Anchors for markers are given in these coordinates.
    static let u: CGFloat = 40
    static let designSize = CGSize(width: 23.9 * u, height: 7.6 * u)

    enum Legend {
        case text(String)                 // single centred label
        case pair(String, String)         // shifted symbol over base
        case mod(String)                  // modifier word, bottom-left
        case fkey(String, String)         // SF Symbol or glyph, plus the F-number
        case symbol(String)               // SF Symbol only
    }

    struct Key {
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        let legend: Legend
    }

    /// Centre of a key in design coordinates, for marker placement.
    static func center(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1) -> CGPoint {
        CGPoint(x: (x + w / 2) * u, y: (y + h / 2) * u)
    }

    static let pad: CGFloat = 0.45, caseTop: CGFloat = 0.55
    static let fnRowY: CGFloat = caseTop + pad, fnRowH: CGFloat = 0.8
    static func rowY(_ r: Int) -> CGFloat { fnRowY + fnRowH + 0.3 + CGFloat(r) }

    // Marker anchors (design coordinates).
    static let easySwitchAnchor = center(pad + 1.5 + 1.125, fnRowY, 1.125, fnRowH)        // F2
    static let fKeysAnchor = center(pad + 1.5 + 1.125 * 7, fnRowY, 1.125, fnRowH)          // F8
    static let fnAnchor = center(pad + 12.25, rowY(4), 1.25, 1)
    static let keysAnchor = center(pad + 20, fnRowY, 1, fnRowH)                           // screenshot key
    static let statusAnchor = CGPoint(x: (23.9 - 2.4) * u, y: 0.3 * u)

    static let keys: [Key] = {
        var k: [Key] = []
        let x0 = pad
        func row(_ r: Int, _ items: [(CGFloat, Legend)], startX: CGFloat = x0) {
            var x = startX
            for (w, l) in items { k.append(Key(x: x, y: rowY(r), w: w, h: 1, legend: l)); x += w }
        }
        // Function row.
        let fns: [Legend] = [
            .fkey("1", "F1"), .fkey("2", "F2"), .fkey("3", "F3"),
            .fkey("rectangle.3.group", "F4"), .fkey("light.min", "F5"), .fkey("light.max", "F6"),
            .fkey("backward.fill", "F7"), .fkey("playpause.fill", "F8"), .fkey("forward.fill", "F9"),
            .fkey("speaker.slash.fill", "F10"), .fkey("speaker.wave.1.fill", "F11"), .fkey("speaker.wave.3.fill", "F12"),
        ]
        k.append(Key(x: x0, y: fnRowY, w: 1.5, h: fnRowH, legend: .mod("esc")))
        for (i, l) in fns.enumerated() { k.append(Key(x: x0 + 1.5 + 1.125 * CGFloat(i), y: fnRowY, w: 1.125, h: fnRowH, legend: l)) }
        let navX = x0 + 15.5, padX = x0 + 19
        for (i, s) in ["sun.min", "sun.max", "square.grid.3x3"].enumerated() {
            k.append(Key(x: navX + CGFloat(i), y: fnRowY, w: 1, h: fnRowH, legend: .symbol(s)))
        }
        for (i, s) in ["plus.forwardslash.minus", "camera.viewfinder", "contextualmenu.and.cursorarrow", "lock"].enumerated() {
            k.append(Key(x: padX + CGFloat(i), y: fnRowY, w: 1, h: fnRowH, legend: .symbol(s)))
        }
        // Main block (US ANSI, Mac legends).
        let nums: [(String, String)] = [("~", "`"), ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"), ("^", "6"),
                                        ("&", "7"), ("*", "8"), ("(", "9"), (")", "0"), ("_", "-"), ("+", "=")]
        row(0, nums.map { (1, .pair($0.0, $0.1)) } + [(2, .mod("delete"))])
        row(1, [(1.5, .mod("tab"))] + "QWERTYUIOP".map { (1, .text(String($0))) }
            + [(1, .pair("{", "[")), (1, .pair("}", "]")), (1.5, .pair("|", "\\"))])
        row(2, [(1.75, .mod("caps lock"))] + "ASDFGHJKL".map { (1, .text(String($0))) }
            + [(1, .pair(":", ";")), (1, .pair("\"", "'")), (2.25, .mod("return"))])
        row(3, [(2.25, .mod("shift"))] + "ZXCVBNM".map { (1, .text(String($0))) }
            + [(1, .pair("<", ",")), (1, .pair(">", ".")), (1, .pair("?", "/")), (2.75, .mod("shift"))])
        row(4, [(1.25, .mod("control")), (1.25, .mod("option")), (1.5, .mod("command")), (6.75, .text("")),
                (1.5, .mod("command")), (1.25, .mod("fn")), (1.25, .mod("option"))])
        // Navigation cluster.
        row(0, [(1, .mod("fn")), (1, .mod("home")), (1, .mod("pg up"))], startX: navX)
        row(1, [(1, .mod("del ⌦")), (1, .mod("end")), (1, .mod("pg dn"))], startX: navX)
        row(3, [(1, .symbol("arrowtriangle.up.fill"))], startX: navX + 1)
        row(4, [(1, .symbol("arrowtriangle.left.fill")), (1, .symbol("arrowtriangle.down.fill")),
                (1, .symbol("arrowtriangle.right.fill"))], startX: navX)
        // Numeric keypad (Mac layout).
        row(0, [(1, .mod("clear")), (1, .text("=")), (1, .text("/")), (1, .text("*"))], startX: padX)
        row(1, [(1, .text("7")), (1, .text("8")), (1, .text("9")), (1, .text("−"))], startX: padX)
        row(2, [(1, .text("4")), (1, .text("5")), (1, .text("6")), (1, .text("+"))], startX: padX)
        row(3, [(1, .text("1")), (1, .text("2")), (1, .text("3"))], startX: padX)
        row(4, [(2, .text("0")), (1, .text("."))], startX: padX)
        k.append(Key(x: padX + 3, y: rowY(3), w: 1, h: 2, legend: .mod("enter")))
        return k
    }()

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / Self.designSize.width
            let u = Self.u * s
            let ink = p.ink, faint = p.faint
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * u, y: y * u, width: w * u, height: h * u) }

            // Case with the raised logo strip.
            let caseRect = r(0, Self.caseTop, 23.9, 7.6 - Self.caseTop - 0.05)
            let strip = Path(roundedRect: r(0.7, 0.04, 23.9 - 1.6, Self.caseTop + 0.6), cornerRadius: 0.35 * u)
            ctx.fill(strip, with: .color(p.paper))
            ctx.stroke(strip, with: .color(ink), lineWidth: 1.2)
            let body = Path(roundedRect: caseRect, cornerRadius: 0.42 * u)
            ctx.fill(body, with: .color(p.paper))
            ctx.stroke(body, with: .color(ink), lineWidth: 1.6)
            ctx.stroke(Path(roundedRect: caseRect.insetBy(dx: 0.1 * u, dy: 0.1 * u), cornerRadius: 0.34 * u),
                       with: .color(ink), lineWidth: 0.6)
            ctx.draw(Text("logi").font(.system(size: 0.42 * u, weight: .bold, design: .rounded)).foregroundColor(ink),
                     at: CGPoint(x: 23.9 / 2 * u, y: 0.3 * u))
            let led = Path(roundedRect: CGRect(x: Self.statusAnchor.x * s - 0.28 * u, y: 0.2 * u, width: 0.56 * u, height: 0.2 * u),
                           cornerRadius: 0.1 * u)
            ctx.stroke(led, with: .color(ink), lineWidth: 0.9)

            // Dash-dot centre lines (drawn under the keycaps, so they show in the gaps like the sheet).
            var centre = Path()
            for x in [23.9 / 2, Self.pad + 17, Self.pad + 4] as [CGFloat] {
                centre.move(to: CGPoint(x: x * u, y: 0.1 * u)); centre.addLine(to: CGPoint(x: x * u, y: 7.55 * u))
            }
            ctx.stroke(centre, with: .color(faint.opacity(0.7)), style: StrokeStyle(lineWidth: 0.6, dash: [10, 3, 2, 3]))

            // Keycaps.
            let gap: CGFloat = 0.07
            for key in Self.keys {
                let outer = r(key.x + gap, key.y + gap, key.w - gap * 2, key.h - gap * 2)
                let cap = Path(roundedRect: outer, cornerRadius: 0.13 * u)
                ctx.fill(cap, with: .color(p.paper))
                ctx.stroke(cap, with: .color(ink), lineWidth: 1.1)
                let inner = outer.insetBy(dx: 0.08 * u, dy: 0.07 * u).offsetBy(dx: 0, dy: -0.02 * u)
                ctx.stroke(Path(roundedRect: inner, cornerRadius: 0.1 * u), with: .color(ink.opacity(0.55)), lineWidth: 0.6)
                legend(ctx, key.legend, in: inner, u: u, ink: ink)
            }
        }
        .accessibilityLabel("MX Keys keyboard drawing")
    }

    private func legend(_ ctx: GraphicsContext, _ l: Legend, in rect: CGRect, u: CGFloat, ink: Color) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func font(_ size: CGFloat, _ w: Font.Weight = .medium) -> Font { .system(size: size * u, weight: w, design: .rounded) }
        switch l {
        case .text(let t):
            ctx.draw(Text(t).font(font(0.34)).foregroundColor(ink), at: c)
        case .pair(let top, let base):
            ctx.draw(Text(top).font(font(0.24)).foregroundColor(ink), at: CGPoint(x: c.x, y: rect.minY + rect.height * 0.3))
            ctx.draw(Text(base).font(font(0.27)).foregroundColor(ink), at: CGPoint(x: c.x, y: rect.minY + rect.height * 0.7))
        case .mod(let t):
            ctx.draw(Text(t).font(font(0.2)).foregroundColor(ink),
                     at: CGPoint(x: rect.minX + 0.1 * u, y: rect.maxY - 0.12 * u), anchor: .bottomLeading)
        case .fkey(let glyph, let f):
            if glyph.count == 1 {
                // Easy-Switch channel: number with its LED dot.
                ctx.draw(Text(glyph).font(font(0.28, .semibold)).foregroundColor(ink), at: CGPoint(x: c.x - 0.08 * u, y: c.y - 0.03 * u))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x + 0.1 * u, y: c.y - 0.2 * u, width: 0.09 * u, height: 0.09 * u)),
                           with: .color(ink), lineWidth: 0.7)
            } else {
                ctx.draw(Text(Image(systemName: glyph)).font(font(0.22)).foregroundColor(ink), at: CGPoint(x: c.x, y: c.y - 0.04 * u))
            }
            ctx.draw(Text(f).font(font(0.13)).foregroundColor(ink.opacity(0.7)),
                     at: CGPoint(x: rect.maxX - 0.05 * u, y: rect.maxY - 0.03 * u), anchor: .bottomTrailing)
        case .symbol(let name):
            ctx.draw(Text(Image(systemName: name)).font(font(0.24)).foregroundColor(ink), at: c)
        }
    }
}
