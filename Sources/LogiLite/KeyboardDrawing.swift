import SwiftUI

/// Vector line drawing of the MX Keys Mac (top view), in the style of the reference sheet: double-outlined
/// keycaps, the raised "logi" strip with its status light, and dash-dot centre lines. Resolution independent.
struct KeyboardDrawing: View {
    let p: WirePalette

    /// Design units: 1 key = `u` points. Anchors for markers are given in these coordinates.
    static let u: CGFloat = 40
    static let designSize = CGSize(width: 23.9 * u, height: 7.6 * u)

    enum Legend {
        case text(String)                         // single centred label
        case pair(String, String)                 // shifted symbol over base
        case mod(String, trailing: Bool)          // modifier word in a bottom corner
        case modSym(String, String)               // modifier glyph over its word (control, option, command)
        case iconWord(String, String)             // SF Symbol over a word (forward delete)
        case fkey(String, String?)                // SF Symbol, plus the F-number bottom right
        case channel(Int, String)                 // Easy-Switch channel: LED, number, computer icon, F-number
        case symbol(String, CGFloat)              // SF Symbol only, at a relative size
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
    /// The top row spans the 15u main block with 14 equal keys: esc, F1–F12, eject.
    static let fW: CGFloat = 15.0 / 14.0
    static let navX = pad + 15.5, padX = pad + 19

    // Marker anchors (design coordinates).
    static let easySwitchAnchor = center(navX + 1, fnRowY, 1, fnRowH)                  // 2 / F14
    static let fKeysAnchor = center(pad + fW * 8, fnRowY, fW, fnRowH)                   // F8
    static let fnAnchor = center(navX, rowY(0))                                        // fn, above delete
    static let keysAnchor = center(padX + 1, fnRowY, 1, fnRowH)                         // screenshot / F17
    static let statusAnchor = CGPoint(x: (23.9 - 1.2) * u, y: 0.3 * u)

    static let keys: [Key] = {
        var k: [Key] = []
        let x0 = pad
        func row(_ r: Int, _ items: [(CGFloat, Legend)], startX: CGFloat = x0) {
            var x = startX
            for (w, l) in items { k.append(Key(x: x, y: rowY(r), w: w, h: 1, legend: l)); x += w }
        }
        func top(_ x: CGFloat, _ w: CGFloat, _ l: Legend) { k.append(Key(x: x, y: fnRowY, w: w, h: fnRowH, legend: l)) }
        // Top row, as printed on the MX Keys Mac.
        let fns: [Legend] = [
            .mod("esc", trailing: false),
            .fkey("sun.min", "F1"), .fkey("sun.max", "F2"), .fkey("rectangle.3.group", "F3"),
            .fkey("square.grid.3x3", "F4"), .fkey("light.min", "F5"), .fkey("light.max", "F6"),
            .fkey("backward.fill", "F7"), .fkey("playpause.fill", "F8"), .fkey("forward.fill", "F9"),
            .fkey("speaker.slash.fill", "F10"), .fkey("speaker.wave.1.fill", "F11"), .fkey("speaker.wave.3.fill", "F12"),
            .fkey("eject.fill", nil),
        ]
        for (i, l) in fns.enumerated() { top(x0 + fW * CGFloat(i), fW, l) }
        for i in 0..<3 { top(navX + CGFloat(i), 1, .channel(i + 1, "F\(13 + i)")) }
        for (i, s) in ["plus.forwardslash.minus", "camera.fill", "list.bullet.rectangle", "lock.open.fill"].enumerated() {
            top(padX + CGFloat(i), 1, .fkey(s, "F\(16 + i)"))
        }
        // Main block (US ANSI, Mac legends).
        let nums: [(String, String)] = [("~", "`"), ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"), ("^", "6"),
                                        ("&", "7"), ("*", "8"), ("(", "9"), (")", "0"), ("_", "-"), ("+", "=")]
        row(0, nums.map { (1, .pair($0.0, $0.1)) } + [(2, .mod("delete", trailing: true))])
        row(1, [(1.5, .mod("tab", trailing: false))] + "QWERTYUIOP".map { (1, .text(String($0))) }
            + [(1, .pair("{", "[")), (1, .pair("}", "]")), (1.5, .pair("|", "\\"))])
        row(2, [(1.75, .mod("caps lock", trailing: false))] + "ASDFGHJKL".map { (1, .text(String($0))) }
            + [(1, .pair(":", ";")), (1, .pair("\"", "'")), (2.25, .mod("return", trailing: true))])
        row(3, [(2.25, .mod("shift", trailing: false))] + "ZXCVBNM".map { (1, .text(String($0))) }
            + [(1, .pair("<", ",")), (1, .pair(">", ".")), (1, .pair("?", "/")), (2.75, .mod("shift", trailing: true))])
        row(4, [(1.5, .modSym("⌃", "control")), (1.25, .modSym("⌥", "option")), (1.5, .modSym("⌘", "command")),
                (6.5, .text("")),
                (1.5, .modSym("⌘", "command")), (1.25, .modSym("⌥", "option")), (1.5, .modSym("⌃", "control"))])
        // Navigation cluster.
        row(0, [(1, .text("fn")), (1, .text("home")), (1, .pair("page", "up"))], startX: navX)
        row(1, [(1, .iconWord("delete.right", "delete")), (1, .text("end")), (1, .pair("page", "down"))], startX: navX)
        row(3, [(1, .symbol("arrowtriangle.up.fill", 0.16))], startX: navX + 1)
        row(4, [(1, .symbol("arrowtriangle.left.fill", 0.16)), (1, .symbol("arrowtriangle.down.fill", 0.16)),
                (1, .symbol("arrowtriangle.right.fill", 0.16))], startX: navX)
        // Numeric keypad (Mac layout).
        row(0, [(1, .text("clear")), (1, .text("=")), (1, .text("/")), (1, .text("*"))], startX: padX)
        row(1, [(1, .text("7")), (1, .text("8")), (1, .text("9")), (1, .text("−"))], startX: padX)
        row(2, [(1, .text("4")), (1, .text("5")), (1, .text("6")), (1, .text("+"))], startX: padX)
        row(3, [(1, .text("1")), (1, .text("2")), (1, .text("3"))], startX: padX)
        row(4, [(2, .text("0")), (1, .text("."))], startX: padX)
        k.append(Key(x: padX + 3, y: rowY(3), w: 1, h: 2, legend: .mod("enter", trailing: true)))
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
        func draw(_ t: Text, _ at: CGPoint, _ anchor: UnitPoint = .center) { ctx.draw(t.foregroundColor(ink), at: at, anchor: anchor) }
        func fLabel(_ f: String) {
            ctx.draw(Text(f).font(font(0.12)).foregroundColor(ink.opacity(0.75)),
                     at: CGPoint(x: rect.maxX - 0.05 * u, y: rect.maxY - 0.03 * u), anchor: .bottomTrailing)
        }
        switch l {
        case .text(let t):
            // Words (fn, home, clear) are set smaller than single characters.
            draw(Text(t).font(font(t.count > 1 ? 0.2 : 0.34)), c)
        case .pair(let top, let base):
            let word = top.count > 1
            draw(Text(top).font(font(word ? 0.18 : 0.24)), CGPoint(x: c.x, y: rect.minY + rect.height * (word ? 0.36 : 0.3)))
            draw(Text(base).font(font(word ? 0.18 : 0.27)), CGPoint(x: c.x, y: rect.minY + rect.height * (word ? 0.64 : 0.7)))
        case .mod(let t, let trailing):
            draw(Text(t).font(font(0.2)),
                 CGPoint(x: trailing ? rect.maxX - 0.1 * u : rect.minX + 0.1 * u, y: rect.maxY - 0.12 * u),
                 trailing ? .bottomTrailing : .bottomLeading)
        case .modSym(let glyph, let word):
            draw(Text(glyph).font(font(0.22)), CGPoint(x: rect.minX + 0.12 * u, y: rect.minY + 0.08 * u), .topLeading)
            draw(Text(word).font(font(0.18)), CGPoint(x: rect.minX + 0.1 * u, y: rect.maxY - 0.1 * u), .bottomLeading)
        case .iconWord(let name, let word):
            draw(Text(Image(systemName: name)).font(font(0.2)), CGPoint(x: c.x, y: rect.minY + rect.height * 0.36))
            draw(Text(word).font(font(0.18)), CGPoint(x: c.x, y: rect.minY + rect.height * 0.68))
        case .fkey(let name, let f):
            draw(Text(Image(systemName: name)).font(font(0.2)), CGPoint(x: c.x, y: c.y - 0.05 * u))
            if let f { fLabel(f) }
        case .channel(let n, let f):
            // LED dot in the corner, then the channel number and the computer/phone icon.
            ctx.stroke(Path(ellipseIn: CGRect(x: rect.minX + 0.06 * u, y: rect.minY + 0.05 * u, width: 0.07 * u, height: 0.07 * u)),
                       with: .color(ink), lineWidth: 0.7)
            draw(Text("\(n)").font(font(0.22, .semibold)), CGPoint(x: c.x - 0.14 * u, y: c.y + 0.02 * u))
            draw(Text(Image(systemName: "laptopcomputer.and.iphone")).font(font(0.17)), CGPoint(x: c.x + 0.14 * u, y: c.y + 0.02 * u))
            fLabel(f)
        case .symbol(let name, let size):
            draw(Text(Image(systemName: name)).font(font(size)), c)
        }
    }
}
