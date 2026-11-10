import AppKit
import SwiftUI

// A technical-drawing ("mechanical works" line art) menu panel: ink hairlines on paper,
// ■ section labels with Japanese sub-captions, a callout schematic of the mouse.

// MARK: - Palette

struct WirePalette {
    let paper: Color
    let ink: Color
    var faint: Color { ink.opacity(0.38) }
    var hairline: Color { ink.opacity(0.22) }

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            paper = Color(red: 0.07, green: 0.07, blue: 0.075)
            ink = Color(red: 0.93, green: 0.93, blue: 0.91)
        } else {
            paper = Color(red: 0.985, green: 0.98, blue: 0.965)
            ink = Color(red: 0.06, green: 0.06, blue: 0.07)
        }
    }
}

enum WireFont {
    static func label(_ size: CGFloat = 9, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let jp = Font.system(size: 8, weight: .medium)
}

// MARK: - Window dragging

/// Lets a SwiftUI region drag its window (title-bar-less panels, and the settings header).
struct WindowDragArea: NSViewRepresentable {
    var onDragged: () -> Void = {}

    func makeNSView(context: Context) -> DragView { DragView(onDragged: onDragged) }
    func updateNSView(_ v: DragView, context: Context) { v.onDragged = onDragged }

    final class DragView: NSView {
        var onDragged: () -> Void
        init(onDragged: @escaping () -> Void) { self.onDragged = onDragged; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("unused") }
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            let before = window?.frame.origin
            window?.performDrag(with: event)   // runs until the mouse is released
            if window?.frame.origin != before { onDragged() }
        }
    }
}

// MARK: - Panel

struct MenuPanel: View {
    @ObservedObject var state: AppState
    let engine: Engine
    let openSettings: () -> Void
    let quitLogiOptions: () -> Void
    let openPrivacy: (String) -> Void
    var onDetach: () -> Void = {}
    var onClose: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    private var p: WirePalette { WirePalette(scheme) }

    private var profileName: String { state.config.profile(for: state.frontBundleID)?.name ?? "All apps" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            WireSection(title: "POWER CELL", jp: "電池", p: p) {
                VStack(spacing: 6) {
                    CellGauge(label: "MOUSE", device: state.mouse, p: p)
                    CellGauge(label: "KEYS", device: state.keyboard, p: p)
                }
            }
            WireSection(title: "CONTROL LAYOUT", jp: "操作系", trailing: profileName.uppercased(), p: p) {
                MouseSchematic(callouts: callouts, connected: state.mouse != nil, p: p)
                    .aspectRatio(MouseSchematic.designSize, contentMode: .fit)
            }
            WireSection(title: "WHEEL", jp: "ホイール", p: p) {
                HStack(spacing: 10) {
                    SegmentSwitch(options: ["RATCHET", "FREE"],
                                  selected: state.freeSpin.map { $0 ? 1 : 0 },
                                  enabled: state.mouse != nil, p: p) { idx in
                        if (idx == 1) != (state.freeSpin ?? false) { engine.devices.mouse?.toggleWheelMode() }
                    }
                    Spacer()
                    WireCheck(label: "SMARTSHIFT", on: state.config.pointer.smartShift, p: p) {
                        state.config.pointer.smartShift.toggle()
                    }
                }
            }
            WireSection(title: "FLOW", jp: "フロー", p: p) {
                HStack(alignment: .center, spacing: 12) {
                    FlowDiagram(enabled: state.config.flow.enabled, edge: state.config.flow.otherMacEdge,
                                peer: state.config.flow.peerName, p: p)
                        .frame(width: 128, height: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        WireCheck(label: "ENABLE", on: state.config.flow.enabled, p: p) { toggleFlow() }
                        Text(state.config.flow.enabled ? state.flowStatus.uppercased() : "OFFLINE")
                            .font(WireFont.label(8)).foregroundStyle(p.faint).lineLimit(2)
                    }
                }
            }
            warnings
            HStack(spacing: 8) {
                WireButton(title: "SETTINGS", shortcut: "⌘,", key: ",", p: p, action: openSettings)
                WireButton(title: "QUIT", shortcut: "⌘Q", key: "q", p: p) { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 372)
        .background(p.paper)
        .overlay(CornerMarks(p: p))
        .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("■ LOGI LITE").font(WireFont.label(12, .bold)).foregroundStyle(p.ink)
                Text("ロジ・ライト").font(WireFont.jp).foregroundStyle(p.faint)
                Spacer()
                Text("Fig. 01 — Control Schematic").font(.system(size: 7, weight: .regular, design: .serif))
                    .italic().foregroundStyle(p.faint)
                headerButton("◐", help: "Display: \(state.appearance.title.lowercased()) (click to change)") {
                    state.appearance = state.appearance.next
                }
                headerButton("⤢", help: "Open full settings", action: openSettings)
                if let onClose { headerButton("×", help: "Close", action: onClose) }
            }
            HStack {
                Text(state.mouse?.name.uppercased() ?? "NO UNIT").font(WireFont.label(8))
                Spacer()
                Text("REV 0.2 · 0x046D:B019").font(WireFont.label(8))
            }
            .foregroundStyle(p.faint)
            Rectangle().fill(p.ink).frame(height: 1)
        }
        .background(WindowDragArea(onDragged: onDetach))
        .help("Drag to move the panel off the menu bar")
    }

    private func headerButton(_ glyph: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(WireFont.label(10, .bold)).foregroundStyle(p.ink)
                .frame(width: 16, height: 16)
                .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder private var warnings: some View {
        let items: [(String, () -> Void)] = [
            state.accessibilityGranted ? nil : ("ALLOW ACCESSIBILITY ACCESS", { openPrivacy("Privacy_Accessibility") }),
            state.inputMonitoringGranted ? nil : ("ALLOW INPUT MONITORING", { openPrivacy("Privacy_ListenEvent") }),
            state.logiOptionsRunning ? ("LOGI OPTIONS RUNNING — STOP IT", quitLogiOptions) : nil,
        ].compactMap { $0 }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { i in
                    Button(action: items[i].1) {
                        HStack(spacing: 6) {
                            Text("!").font(WireFont.label(9, .bold))
                                .frame(width: 13, height: 13)
                                .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
                            Text(items[i].0).font(WireFont.label(9, .semibold))
                            Spacer()
                            Text("→").font(WireFont.label(9))
                        }
                        .foregroundStyle(p.ink)
                        .padding(6)
                        .overlay(Rectangle().strokeBorder(p.ink, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func toggleFlow() {
        if state.config.flow.secret == nil { state.config.flow.secret = FlowService.newSecret() }
        state.config.flow.enabled.toggle()
    }

    private var callouts: [MouseSchematic.Callout] {
        let bid = state.frontBundleID
        func describe(_ b: ButtonID) -> String {
            let c = state.config.effectiveButton(b, bundleID: bid)
            if c.useGestures { return "GESTURES · " + short(c.gesture(.click)) }
            return short(c.action)
        }
        func short(_ a: Action) -> String {
            let s = a.kind == .passthrough ? "NATIVE" : a.summary.uppercased()
            return s.count > 18 ? String(s.prefix(17)) + "…" : s
        }
        return [
            .init(index: 1, part: .wheel, title: "MIDDLE", value: describe(.middle)),
            .init(index: 2, part: .wheelMode, title: "WHEEL BTN", value: describe(.wheelMode)),
            .init(index: 3, part: .thumbWheel, title: "THUMB WHEEL",
                  value: state.config.effectiveThumbWheel(bundleID: bid).title.uppercased()),
            .init(index: 4, part: .forward, title: "FORWARD", value: describe(.forward)),
            .init(index: 5, part: .back, title: "BACK", value: describe(.back)),
            .init(index: 6, part: .gesture, title: "GESTURE", value: describe(.gesture)),
        ]
    }
}

// MARK: - Building blocks

struct WireSection<Content: View>: View {
    let title: String
    let jp: String
    var trailing: String? = nil
    let p: WirePalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("■ " + title).font(WireFont.label(9, .bold)).foregroundStyle(p.ink)
                Text(jp).font(WireFont.jp).foregroundStyle(p.faint)
                Rectangle().fill(p.hairline).frame(height: 1).alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 3 }
                if let trailing {
                    Text(trailing).font(WireFont.label(8, .semibold)).foregroundStyle(p.ink).lineLimit(1)
                }
            }
            content()
        }
    }
}

struct CellGauge: View {
    let label: String
    let device: DeviceSnapshot?
    let p: WirePalette
    var cells = 12

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(WireFont.label(8, .semibold)).foregroundStyle(p.ink).frame(width: 40, alignment: .leading)
            // While charging, one extra cell "fills" in a slow sweep, like a charge indicator.
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let tick = Int(timeline.date.timeIntervalSinceReferenceDate * 2)
                Canvas { ctx, size in draw(ctx, size, tick: tick) }
            }
            .frame(height: 11)
            VStack(alignment: .trailing, spacing: 0) {
                Text(readout).font(WireFont.label(9, .semibold)).foregroundStyle(p.ink)
                if let d = device, d.chargeState != .discharging {
                    Text(d.chargeState.label).font(WireFont.label(6, .bold)).foregroundStyle(p.faint)
                }
            }
            .frame(width: 58, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) battery \(readout) \(device?.chargeState.label.lowercased() ?? "")")
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, tick: Int) {
        let gap: CGFloat = 2
        let w = (size.width - gap * CGFloat(cells - 1)) / CGFloat(cells)
        let known = device?.battery
        let filled = known.map { Int((Double($0) / 100 * Double(cells)).rounded(.up)) } ?? 0
        let charging = device?.chargeState == .charging || device?.chargeState == .slowCharging
        // Sweep from the current level to the end; with no reading, sweep the whole gauge.
        let sweepStart = min(filled, cells - 1)
        let sweep = charging ? sweepStart + tick % max(cells - sweepStart, 1) : -1
        for i in 0..<cells {
            let r = CGRect(x: CGFloat(i) * (w + gap), y: 0, width: w, height: size.height).insetBy(dx: 0.5, dy: 0.5)
            let solid = i < filled
            let pulsing = charging && i >= sweepStart && i <= sweep
            ctx.stroke(Path(r), with: .color(solid || pulsing ? p.ink : p.hairline),
                       style: StrokeStyle(lineWidth: 1, dash: pulsing && !solid ? [2, 1.5] : []))
            guard solid || pulsing else { continue }
            ctx.drawLayer { layer in
                layer.clip(to: Path(r))
                var hatch = Path()
                var x = r.minX - r.height
                while x < r.maxX { hatch.move(to: CGPoint(x: x, y: r.maxY)); hatch.addLine(to: CGPoint(x: x + r.height, y: r.minY)); x += 3 }
                layer.stroke(hatch, with: .color(solid ? p.ink : p.faint), lineWidth: 0.8)
            }
        }
    }

    private var readout: String {
        guard let d = device else { return "— —" }
        if d.chargeState == .full { return "100% ⚡︎" }
        if d.chargeState == .error { return "ERR" }
        let level = d.battery.map { "\($0)%" }
        if d.charging { return (level ?? "") + "⚡︎" }
        return level ?? "???"
    }
}

struct SegmentSwitch: View {
    let options: [String]
    let selected: Int?
    let enabled: Bool
    let p: WirePalette
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = selected == i
                Button { onSelect(i) } label: {
                    Text(options[i]).font(WireFont.label(9, .semibold))
                        .foregroundStyle(on ? p.paper : p.ink)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(on ? p.ink : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rectangle().fill(p.ink).frame(width: 1) }
            }
        }
        .fixedSize()
        .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

struct WireCheck: View {
    let label: String
    let on: Bool
    let p: WirePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    Rectangle().strokeBorder(p.ink, lineWidth: 1)
                    if on {
                        Path { path in
                            path.move(to: CGPoint(x: 2.5, y: 2.5)); path.addLine(to: CGPoint(x: 8.5, y: 8.5))
                            path.move(to: CGPoint(x: 8.5, y: 2.5)); path.addLine(to: CGPoint(x: 2.5, y: 8.5))
                        }
                        .stroke(p.ink, lineWidth: 1.2)
                    }
                }
                .frame(width: 11, height: 11)
                Text(label).font(WireFont.label(9, .semibold)).foregroundStyle(p.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WireButton: View {
    let title: String
    let shortcut: String
    var key: KeyEquivalent? = nil
    let p: WirePalette
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(WireFont.label(10, .bold))
                Spacer()
                Text(shortcut).font(WireFont.label(9))
            }
            .foregroundStyle(hover ? p.paper : p.ink)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(hover ? p.ink : .clear)
            .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key ?? KeyEquivalent("\u{0}"), modifiers: key == nil ? [] : .command)
        .onHover { hover = $0 }
    }
}

struct CornerMarks: View {
    let p: WirePalette
    var body: some View {
        Canvas { ctx, size in
            let l: CGFloat = 9, i: CGFloat = 4
            var path = Path()
            for (x, y, sx, sy) in [(i, i, 1.0, 1.0), (size.width - i, i, -1.0, 1.0),
                                   (i, size.height - i, 1.0, -1.0), (size.width - i, size.height - i, -1.0, -1.0)] {
                path.move(to: CGPoint(x: x, y: y + sy * l)); path.addLine(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + sx * l, y: y))
            }
            ctx.stroke(path, with: .color(p.ink), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Flow diagram

struct FlowDiagram: View {
    let enabled: Bool
    let edge: FlowEdge
    let peer: String?
    let p: WirePalette

    var body: some View {
        Canvas { ctx, size in
            let w: CGFloat = 44, h: CGFloat = 28
            let thisRect: CGRect, otherRect: CGRect
            switch edge {
            case .left, .top:
                otherRect = CGRect(x: 2, y: 2, width: w, height: h)
                thisRect = CGRect(x: size.width - w - 2, y: 2, width: w, height: h)
            case .right, .bottom:
                thisRect = CGRect(x: 2, y: 2, width: w, height: h)
                otherRect = CGRect(x: size.width - w - 2, y: 2, width: w, height: h)
            }
            for (r, solid) in [(thisRect, true), (otherRect, enabled)] {
                let style = StrokeStyle(lineWidth: 1, dash: solid ? [] : [3, 2])
                ctx.stroke(Path(r), with: .color(p.ink), style: style)
                ctx.stroke(Path(r.insetBy(dx: 3, dy: 3)), with: .color(p.hairline), lineWidth: 0.8)
                var stand = Path()
                stand.move(to: CGPoint(x: r.midX, y: r.maxY)); stand.addLine(to: CGPoint(x: r.midX, y: r.maxY + 5))
                stand.move(to: CGPoint(x: r.midX - 8, y: r.maxY + 5)); stand.addLine(to: CGPoint(x: r.midX + 8, y: r.maxY + 5))
                ctx.stroke(stand, with: .color(p.ink), style: style)
            }
            // Arrow between screens.
            let y = thisRect.midY
            let a = CGPoint(x: min(thisRect.maxX, otherRect.maxX) + 4, y: y)
            let b = CGPoint(x: max(thisRect.minX, otherRect.minX) - 4, y: y)
            var arrow = Path()
            arrow.move(to: a); arrow.addLine(to: b)
            for tip in [a, b] {
                let dir: CGFloat = tip == a ? 1 : -1
                arrow.move(to: CGPoint(x: tip.x + dir * 4, y: y - 3)); arrow.addLine(to: tip)
                arrow.addLine(to: CGPoint(x: tip.x + dir * 4, y: y + 3))
            }
            ctx.stroke(arrow, with: .color(enabled ? p.ink : p.faint), style: StrokeStyle(lineWidth: 1, dash: enabled ? [] : [2, 2]))
            ctx.draw(Text("A").font(WireFont.label(8, .bold)).foregroundColor(p.ink), at: CGPoint(x: thisRect.midX, y: thisRect.midY))
            ctx.draw(Text("B").font(WireFont.label(8, .bold)).foregroundColor(enabled ? p.ink : p.faint),
                     at: CGPoint(x: otherRect.midX, y: otherRect.midY))
            ctx.draw(Text("THIS").font(WireFont.label(6)).foregroundColor(p.faint), at: CGPoint(x: thisRect.midX, y: size.height - 3))
            ctx.draw(Text((peer ?? "OTHER").uppercased().prefix(10)).font(WireFont.label(6)).foregroundColor(p.faint),
                     at: CGPoint(x: otherRect.midX, y: size.height - 3))
        }
    }
}

// MARK: - Panel window

/// Borderless panel anchored under the menu bar icon (crisp rectangle; no popover arrow or material).
final class MenuPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var monitor: Any?
    /// Once dragged off the menu bar the panel stays put until closed explicitly.
    private(set) var pinned = false
    private let makeView: () -> AnyView

    init(makeView: @escaping () -> AnyView) { self.makeView = makeView }

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(relativeTo button: NSStatusBarButton) {
        isShown ? close() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        let host = NSHostingView(rootView: makeView())
        host.layout()
        let size = host.fittingSize
        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.delegate = self
        p.isReleasedWhenClosed = false

        if let bw = button.window {
            let r = bw.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = bw.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            var x = r.midX - size.width / 2
            x = min(max(x, screen.minX + 6), screen.maxX - size.width - 6)
            p.setFrameOrigin(NSPoint(x: x, y: r.minY - size.height - 4))
        }
        panel = p
        pinned = false
        p.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.pinned else { return }
            self.close()
        }
    }

    /// Called when the user drags the panel: keep it open as a floating window.
    func pin() {
        guard let p = panel else { return }
        pinned = true
        p.level = .floating
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    func close() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
        pinned = false
    }

    func windowDidResignKey(_ notification: Notification) { if !pinned { close() } }
}

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { (delegate as? MenuPanelController)?.close() }
}
