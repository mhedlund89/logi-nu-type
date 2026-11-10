import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Settings window laid out like Logi Options (device drawing with clickable callouts, action list beside it,
// per-app profiles across the top), drawn as a line-art mechanical spec sheet.

struct SettingsView: View {
    @ObservedObject var state: AppState
    let engine: Engine
    @Environment(\.colorScheme) private var scheme
    @State private var tab: SettingsTab

    /// false only for --render-panel (ImageRenderer can't draw ScrollView contents).
    private let scrolls: Bool

    init(state: AppState, engine: Engine, initialTab: SettingsTab = .mouse, scrolls: Bool = true) {
        self.state = state
        self.engine = engine
        self.scrolls = scrolls
        _tab = State(initialValue: initialTab)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case mouse = "MOUSE", pointer = "POINT & SCROLL", flow = "FLOW", device = "DEVICE"
        var id: String { rawValue }
        var jp: String {
            switch self { case .mouse: return "操作系"; case .pointer: return "ポインタ"; case .flow: return "フロー"; case .device: return "装置" }
        }
    }

    var body: some View {
        let p = WirePalette(scheme)
        VStack(spacing: 0) {
            header(p)
            Rectangle().fill(p.ink).frame(height: 1)
            if scrolls { ScrollView { content(p) } } else { content(p); Spacer(minLength: 0) }
        }
        .background(p.paper)
        .overlay(CornerMarks(p: p))
        .frame(minWidth: 900, minHeight: 660)
    }

    private func content(_ p: WirePalette) -> some View {
        Group {
            switch tab {
            case .mouse: MouseTab(state: state, p: p)
            case .pointer: PointerTab(state: state, engine: engine, p: p)
            case .flow: FlowTab(state: state, p: p)
            case .device: DeviceTab(state: state, p: p)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func header(_ p: WirePalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("■ LOGI LITE").font(WireFont.label(15, .bold)).foregroundStyle(p.ink)
                        Text("ロジ・ライト  設定").font(WireFont.jp).foregroundStyle(p.faint)
                    }
                    Text("\(state.mouse?.name.uppercased() ?? "NO UNIT CONNECTED") · SPEC SHEET")
                        .font(WireFont.label(9)).foregroundStyle(p.faint)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    CellGauge(label: "MOUSE", device: state.mouse, p: p, cells: 10).frame(width: 230)
                    CellGauge(label: "KEYS", device: state.keyboard, p: p, cells: 10).frame(width: 230)
                    HStack(spacing: 8) {
                        Text("DISPLAY").font(WireFont.label(8, .semibold)).foregroundStyle(p.faint)
                        SegmentSwitch(options: Appearance.allCases.map(\.title),
                                      selected: Appearance.allCases.firstIndex(of: state.appearance),
                                      enabled: true, p: p) { state.appearance = Appearance.allCases[$0] }
                    }
                    .padding(.top, 4)
                }
            }
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { t in
                    let on = tab == t
                    Button { tab = t } label: {
                        HStack(spacing: 5) {
                            Text(t.rawValue).font(WireFont.label(10, .bold))
                            Text(t.jp).font(WireFont.jp).opacity(0.6)
                        }
                        .foregroundStyle(on ? p.paper : p.ink)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(on ? p.ink : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    Rectangle().fill(p.ink).frame(width: 1)
                }
            }
            .fixedSize()
            .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)   // clear the transparent title bar's window buttons
        .padding(.bottom, 14)
        .background(WindowDragArea())   // drag the window from anywhere in the header
    }
}

// MARK: - Shared building blocks

struct WireCard<Content: View>: View {
    let title: String
    let jp: String
    var fig: String? = nil
    let p: WirePalette
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("■ " + title).font(WireFont.label(10, .bold)).foregroundStyle(p.ink)
                Text(jp).font(WireFont.jp).foregroundStyle(p.faint)
                Spacer()
                if let fig { Text(fig).font(WireFont.label(7)).foregroundStyle(p.faint) }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
    }
}

struct WireMiniButton: View {
    let title: String
    let p: WirePalette
    var enabled = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title).font(WireFont.label(9, .bold))
                .foregroundStyle(hover && enabled ? p.paper : p.ink)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(hover && enabled ? p.ink : .clear)
                .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

struct WireRadio: View {
    let title: String
    let on: Bool
    let p: WirePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().strokeBorder(p.ink, lineWidth: 1)
                    if on { Circle().fill(p.ink).padding(2.5) }
                }
                .frame(width: 11, height: 11)
                Text(title).font(WireFont.label(9, on ? .bold : .regular)).foregroundStyle(p.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct WireTextField: View {
    let placeholder: String
    @Binding var text: String
    let p: WirePalette

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(WireFont.label(10))
            .foregroundStyle(p.ink)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .overlay(Rectangle().strokeBorder(p.ink, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
    }
}

/// Ruler-style slider: hairline track with tick marks and a square outlined thumb.
struct WireSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var ticks = 10
    let p: WirePalette
    var onCommit: () -> Void = {}

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 10
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let mid = size.height / 2
                    var track = Path()
                    track.move(to: CGPoint(x: 5, y: mid)); track.addLine(to: CGPoint(x: size.width - 5, y: mid))
                    ctx.stroke(track, with: .color(p.hairline), lineWidth: 1)
                    var fill = Path()
                    fill.move(to: CGPoint(x: 5, y: mid)); fill.addLine(to: CGPoint(x: 5 + t * w, y: mid))
                    ctx.stroke(fill, with: .color(p.ink), lineWidth: 2)
                    var marks = Path()
                    for i in 0...ticks {
                        let x = 5 + CGFloat(i) / CGFloat(ticks) * w
                        let h: CGFloat = i % 5 == 0 ? 6 : 3
                        marks.move(to: CGPoint(x: x, y: mid + 4)); marks.addLine(to: CGPoint(x: x, y: mid + 4 + h))
                    }
                    ctx.stroke(marks, with: .color(p.faint), lineWidth: 0.8)
                }
                Rectangle().fill(p.paper)
                    .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1.2))
                    .frame(width: 10, height: 14)
                    .position(x: 5 + t * w, y: g.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let raw = range.lowerBound + Double(max(0, min(1, (v.location.x - 5) / w))) * (range.upperBound - range.lowerBound)
                    value = (raw / step).rounded() * step
                }
                .onEnded { _ in onCommit() })
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityValue("\(Int(value))")
        .accessibilityAdjustableAction { dir in
            value = dir == .increment ? min(range.upperBound, value + step) : max(range.lowerBound, value - step)
            onCommit()
        }
    }
}

// MARK: - MOUSE tab

private enum ProfileSelection: Hashable { case all, app(UUID) }

struct MouseTab: View {
    @ObservedObject var state: AppState
    let p: WirePalette
    @State private var selection: ProfileSelection = .all
    @State private var part: MouseSchematic.Part = .gesture
    @State private var direction: GestureDirection = .click

    private var profileID: UUID? { if case .app(let id) = selection { return id }; return nil }
    private var isDefault: Bool { profileID == nil }

    private var profile: Binding<Profile> {
        Binding(
            get: { profileID.flatMap { id in state.config.apps.first { $0.id == id } } ?? state.config.defaults },
            set: { p in
                if let i = state.config.apps.firstIndex(where: { $0.id == p.id }) { state.config.apps[i] = p }
                else { state.config.defaults = p }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            profileBar
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    MouseIllustration(callouts: callouts, connected: state.mouse != nil, p: p,
                                      selected: callouts.first { $0.part == part }?.index,
                                      legendColumns: 3, onSelect: { part = $0 })
                        .frame(width: 560)
                    Text("SELECT A NUMBERED MARKER OR A LEGEND ROW TO ASSIGN IT")
                        .font(WireFont.label(8)).foregroundStyle(p.faint)
                }
                inspector.frame(minWidth: 300, maxWidth: .infinity)
            }
        }
        .onChange(of: part) { _, _ in direction = .click }
    }

    private var profileBar: some View {
        HStack(spacing: 6) {
            Text("PROFILE").font(WireFont.label(8, .semibold)).foregroundStyle(p.faint)
            chip("ALL APPS", .all)
            ForEach(state.config.apps) { app in chip(app.name.uppercased(), .app(app.id)) }
            WireMiniButton(title: "+ ADD APP", p: p) { addApp() }
            Spacer()
            if !isDefault {
                WireMiniButton(title: "REMOVE PROFILE", p: p) {
                    state.config.apps.removeAll { $0.id == profileID }
                    selection = .all
                }
            }
        }
    }

    private func chip(_ title: String, _ sel: ProfileSelection) -> some View {
        let on = selection == sel
        return Button { selection = sel } label: {
            Text(title).font(WireFont.label(9, .semibold)).lineLimit(1)
                .foregroundStyle(on ? p.paper : p.ink)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(on ? p.ink : .clear)
                .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var callouts: [MouseSchematic.Callout] {
        let prof = profile.wrappedValue
        func cfg(_ b: ButtonID) -> ButtonConfig {
            prof.button(b) ?? state.config.defaults.button(b) ?? ButtonConfig(action: Action(.passthrough))
        }
        func short(_ a: Action) -> String {
            let s = a.kind == .passthrough ? "NATIVE" : a.summary.uppercased()
            return s.count > 18 ? String(s.prefix(17)) + "…" : s
        }
        func describe(_ b: ButtonID) -> String {
            let c = cfg(b)
            let inherited = !isDefault && prof.button(b) == nil ? "↳ " : ""
            return inherited + (c.useGestures ? "GESTURES · " + short(c.gesture(.click)) : short(c.action))
        }
        let thumb = prof.thumbWheel ?? state.config.defaults.thumbWheel ?? .horizontalScroll
        return [
            .init(index: 1, part: .wheel, title: "MIDDLE", value: describe(.middle)),
            .init(index: 2, part: .wheelMode, title: "WHEEL BTN", value: describe(.wheelMode)),
            .init(index: 3, part: .thumbWheel, title: "THUMB WHEEL",
                  value: (!isDefault && prof.thumbWheel == nil ? "↳ " : "") + thumb.title.uppercased()),
            .init(index: 4, part: .forward, title: "FORWARD", value: describe(.forward)),
            .init(index: 5, part: .back, title: "BACK", value: describe(.back)),
            .init(index: 6, part: .gesture, title: "GESTURE", value: describe(.gesture)),
        ]
    }

    private var buttonForPart: ButtonID? {
        switch part {
        case .wheel: return .middle
        case .wheelMode: return .wheelMode
        case .forward: return .forward
        case .back: return .back
        case .gesture: return .gesture
        case .thumbWheel: return nil
        }
    }

    @ViewBuilder private var inspector: some View {
        let index = callouts.first { $0.part == part }?.index ?? 0
        if let b = buttonForPart {
            ButtonInspector(index: index, button: b, isDefault: isDefault, profileName: profile.wrappedValue.name,
                            config: Binding(get: { profile.wrappedValue.buttons[b.rawValue] },
                                            set: { profile.wrappedValue.buttons[b.rawValue] = $0 }),
                            fallback: state.config.defaults.button(b) ?? ButtonConfig(action: Action(.passthrough)),
                            direction: $direction, p: p)
        } else {
            WireCard(title: "\(index) THUMB WHEEL", jp: "サムホイール", fig: profile.wrappedValue.name.uppercased(), p: p) {
                if !isDefault {
                    WireCheck(label: "SAME AS ALL APPS", on: profile.wrappedValue.thumbWheel == nil, p: p) {
                        profile.wrappedValue.thumbWheel = profile.wrappedValue.thumbWheel == nil
                            ? (state.config.defaults.thumbWheel ?? .horizontalScroll) : nil
                    }
                }
                if isDefault || profile.wrappedValue.thumbWheel != nil {
                    ForEach(ThumbWheelAction.allCases) { a in
                        WireRadio(title: a.title.uppercased(),
                                  on: (profile.wrappedValue.thumbWheel ?? .horizontalScroll) == a, p: p) {
                            profile.wrappedValue.thumbWheel = a
                        }
                    }
                }
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        if let existing = state.config.apps.first(where: { $0.bundleID == id }) { selection = .app(existing.id); return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let new = Profile(name: name, bundleID: id, appPath: url.path)
        state.config.apps.append(new)
        selection = .app(new.id)
    }
}

/// The mouse drawing rendered natively (sharp), with invisible hit targets over each callout label and part.
struct InteractiveSchematic: View {
    let callouts: [MouseSchematic.Callout]
    let connected: Bool
    let p: WirePalette
    @Binding var selected: MouseSchematic.Part
    var width: CGFloat = 560

    var body: some View {
        let design = MouseSchematic.designSize(.side)
        let s = width / design.width
        let origin = MouseSchematic.origin(.side)
        ZStack(alignment: .topLeading) {
            MouseSchematic(callouts: callouts, connected: connected, p: p,
                           selected: callouts.first { $0.part == selected }?.index, layout: .side)
                .frame(width: width, height: design.height * s)
            ForEach(callouts, id: \.index) { c in
                let r = MouseSchematic.hitRect(for: c, in: callouts, layout: .side)
                hit(c).frame(width: r.width * s, height: r.height * s).position(x: r.midX * s, y: r.midY * s)
                if let a = MouseSchematic.anchors[c.part] {
                    hit(c).frame(width: 16 * s, height: 16 * s).position(x: (origin.x + a.x) * s, y: (origin.y + a.y) * s)
                }
            }
        }
        .frame(width: width, height: design.height * s, alignment: .topLeading)
    }

    private func hit(_ c: MouseSchematic.Callout) -> some View {
        Button { selected = c.part } label: { Rectangle().fill(Color.clear).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel("\(c.index). \(c.title): \(c.value)")
    }
}

struct ButtonInspector: View {
    let index: Int
    let button: ButtonID
    let isDefault: Bool
    let profileName: String
    @Binding var config: ButtonConfig?
    let fallback: ButtonConfig
    @Binding var direction: GestureDirection
    let p: WirePalette

    var body: some View {
        WireCard(title: "\(index) \(button.title.uppercased())", jp: "ボタン割当", fig: profileName.uppercased(), p: p) {
            if !isDefault {
                WireCheck(label: "SAME AS ALL APPS", on: config == nil, p: p) { config = config == nil ? fallback : nil }
            }
            if !isDefault && config == nil {
                Text("USES: " + describe(fallback)).font(WireFont.label(9)).foregroundStyle(p.faint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let cfg = Binding<ButtonConfig>(get: { config ?? fallback }, set: { config = $0 })
                WireCheck(label: "HOLD + MOVE FOR GESTURES", on: cfg.wrappedValue.useGestures, p: p) {
                    cfg.wrappedValue.useGestures.toggle()
                }
                if cfg.wrappedValue.useGestures {
                    GestureCross(config: cfg.wrappedValue, selected: $direction, p: p)
                    Text("ASSIGNING: \(direction.title.uppercased())").font(WireFont.label(8, .semibold)).foregroundStyle(p.faint)
                    ActionList(action: Binding(get: { cfg.wrappedValue.gesture(direction) },
                                               set: { cfg.wrappedValue.gestures[direction.rawValue] = $0 }), p: p)
                } else {
                    ActionList(action: cfg.action, p: p)
                }
            }
        }
    }

    private func describe(_ c: ButtonConfig) -> String {
        if c.useGestures {
            return "GESTURES — " + GestureDirection.allCases.map { "\($0.rawValue.uppercased()) \(c.gesture($0).summary.uppercased())" }
                .joined(separator: " · ")
        }
        return c.action.summary.uppercased()
    }
}

/// Up / left / click / right / down boxes in a cross, like a gesture diagram.
struct GestureCross: View {
    let config: ButtonConfig
    @Binding var selected: GestureDirection
    let p: WirePalette

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); cell(.up, "▲"); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
            GridRow { cell(.left, "◀"); cell(.click, "●"); cell(.right, "▶") }
            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); cell(.down, "▼"); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
        }
        .frame(maxWidth: .infinity)
    }

    private func cell(_ d: GestureDirection, _ glyph: String) -> some View {
        let on = selected == d
        let a = config.gesture(d)
        let short: [ActionKind: String] = [
            .passthrough: "NATIVE", .desktopLeft: "DESKTOP ←", .desktopRight: "DESKTOP →", .missionControl: "MISSION CTRL",
            .previousTrack: "PREV TRACK", .toggleWheelMode: "WHEEL MODE", .screenshot: "SCREENSHOT", .launchpad: "APPS",
        ]
        let summary = short[a.kind] ?? a.summary.uppercased()
        return Button { selected = d } label: {
            VStack(spacing: 2) {
                Text(glyph).font(.system(size: 9))
                Text(summary.count > 14 ? String(summary.prefix(13)) + "…" : summary)
                    .font(WireFont.label(7, .semibold)).lineLimit(1)
            }
            .foregroundStyle(on ? p.paper : p.ink)
            .frame(width: 104, height: 34)
            .background(on ? p.ink : .clear)
            .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.title): \(a.summary)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct ActionList: View {
    @Binding var action: Action
    let p: WirePalette

    private static let groups: [(String, [ActionKind])] = [
        ("DEFAULT", [.passthrough, .nothing]),
        ("SYSTEM", [.missionControl, .appExpose, .showDesktop, .launchpad, .desktopLeft, .desktopRight, .screenshot]),
        ("NAVIGATION", [.browserBack, .browserForward, .middleClick, .toggleWheelMode]),
        ("EDITING", [.copy, .paste, .undo, .redo]),
        ("MEDIA", [.playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .mute]),
        ("CUSTOM", [.keystroke, .openApp, .openURL]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.groups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(group.0).font(WireFont.label(7, .bold)).foregroundStyle(p.faint)
                        Rectangle().fill(p.hairline).frame(height: 1)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                              alignment: .leading, spacing: 5) {
                        ForEach(group.1) { kind in
                            WireRadio(title: kind.title.replacingOccurrences(of: "…", with: "").uppercased(),
                                      on: action.kind == kind, p: p) { action.kind = kind }
                        }
                    }
                }
            }
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        switch action.kind {
        case .keystroke:
            HStack { Text("SHORTCUT").font(WireFont.label(8, .semibold)).foregroundStyle(p.faint); KeyRecorder(combo: $action.keys, p: p) }
        case .openApp:
            HStack {
                Text("APP").font(WireFont.label(8, .semibold)).foregroundStyle(p.faint)
                WireMiniButton(title: action.path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.uppercased() } ?? "CHOOSE APP…", p: p) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK { action.path = panel.url?.path }
                }
            }
        case .openURL:
            WireTextField(placeholder: "https://…", text: Binding(get: { action.url ?? "" }, set: { action.url = $0 }), p: p)
        default:
            EmptyView()
        }
    }
}

struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    let p: WirePalette
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? "PRESS SHORTCUT… (ESC CANCELS)" : (combo?.display ?? "RECORD SHORTCUT"))
                .font(WireFont.label(10, .bold))
                .foregroundStyle(recording ? p.paper : p.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(recording ? p.ink : .clear)
                .overlay(Rectangle().strokeBorder(p.ink, style: StrokeStyle(lineWidth: 1, dash: recording ? [] : [3, 2])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            if e.keyCode == 53 && mods.isEmpty { stop(); return nil }
            combo = KeyCombo(keyCode: e.keyCode, modifiers: Self.cgFlags(mods).rawValue, display: Self.display(mods, e))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    static func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags {
        var f = CGEventFlags()
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.shift) { f.insert(.maskShift) }
        return f
    }

    static func display(_ m: NSEvent.ModifierFlags, _ e: NSEvent) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let names: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        s += names[e.keyCode] ?? (e.charactersIgnoringModifiers?.uppercased() ?? "Key \(e.keyCode)")
        return s
    }
}

// MARK: - POINT & SCROLL tab

struct PointerTab: View {
    @ObservedObject var state: AppState
    let engine: Engine
    let p: WirePalette
    @State private var dpi: Double = 1000

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WireCard(title: "POINTER SPEED", jp: "ポインタ速度", fig: "FIG. 2-1", p: p) {
                if state.mouse != nil {
                    HStack(spacing: 14) {
                        Text("200").font(WireFont.label(8)).foregroundStyle(p.faint)
                        WireSlider(value: $dpi, range: 200...4000, step: 50, ticks: 38, p: p) { engine.setDPI(Int(dpi)) }
                        Text("4000").font(WireFont.label(8)).foregroundStyle(p.faint)
                        Text("\(Int(dpi)) DPI").font(WireFont.label(12, .bold)).foregroundStyle(p.ink)
                            .monospacedDigit().frame(width: 90, alignment: .trailing)
                    }
                    Text("SENSOR RESOLUTION. MACOS TRACKING SPEED STILL APPLIES ON TOP.").font(WireFont.label(8)).foregroundStyle(p.faint)
                } else {
                    Text("— UNIT NOT CONNECTED —").font(WireFont.label(9, .bold)).foregroundStyle(p.faint)
                }
            }
            WireCard(title: "SCROLL WHEEL", jp: "ホイール", fig: "FIG. 2-2", p: p) {
                HStack(spacing: 14) {
                    Text("MODE").font(WireFont.label(8, .semibold)).foregroundStyle(p.faint)
                    SegmentSwitch(options: ["RATCHET", "FREE SPIN"], selected: state.freeSpin.map { $0 ? 1 : 0 },
                                  enabled: state.mouse != nil, p: p) { i in
                        if (i == 1) != (state.freeSpin ?? false) { engine.devices.mouse?.toggleWheelMode() }
                    }
                }
                WireCheck(label: "SMARTSHIFT — FLICK THE WHEEL TO FREE-SPIN AUTOMATICALLY", on: state.config.pointer.smartShift, p: p) {
                    state.config.pointer.smartShift.toggle()
                }
                if state.config.pointer.smartShift {
                    HStack(spacing: 14) {
                        Text("SENSITIVITY").font(WireFont.label(8, .semibold)).foregroundStyle(p.faint)
                        WireSlider(value: Binding(get: { Double(state.config.pointer.smartShiftThreshold) },
                                                  set: { state.config.pointer.smartShiftThreshold = Int($0) }),
                                   range: 1...50, step: 1, ticks: 10, p: p)
                        Text("\(state.config.pointer.smartShiftThreshold)").font(WireFont.label(11, .bold)).foregroundStyle(p.ink)
                            .monospacedDigit().frame(width: 30, alignment: .trailing)
                    }
                }
            }
            WireCard(title: "DIRECTION", jp: "方向", fig: "FIG. 2-3", p: p) {
                WireCheck(label: "REVERSE SCROLL DIRECTION (THIS MOUSE ONLY)", on: state.config.pointer.reverseWheel, p: p) {
                    state.config.pointer.reverseWheel.toggle()
                }
                WireCheck(label: "REVERSE THUMB WHEEL DIRECTION", on: state.config.pointer.reverseThumbWheel, p: p) {
                    state.config.pointer.reverseThumbWheel.toggle()
                }
            }
        }
        .onAppear { dpi = Double(state.dpi ?? state.config.pointer.dpi ?? 1000) }
        .onChange(of: state.dpi) { _, new in if let new { dpi = Double(new) } }
    }
}

// MARK: - FLOW tab

struct FlowTab: View {
    @ObservedObject var state: AppState
    let p: WirePalette
    @State private var entered = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WireCard(title: "FLOW", jp: "フロー", fig: "FIG. 3-1", p: p) {
                HStack(alignment: .center, spacing: 24) {
                    FlowEdgePicker(edge: $state.config.flow.otherMacEdge, enabled: state.config.flow.enabled,
                                   peer: state.config.flow.peerName, p: p)
                        .frame(width: 300, height: 190)
                    VStack(alignment: .leading, spacing: 10) {
                        WireCheck(label: "ENABLE FLOW", on: state.config.flow.enabled, p: p) {
                            if state.config.flow.secret == nil { state.config.flow.secret = FlowService.newSecret() }
                            state.config.flow.enabled.toggle()
                        }
                        Text("STATUS: " + (state.config.flow.enabled ? state.flowStatus.uppercased() : "OFF"))
                            .font(WireFont.label(9, .semibold)).foregroundStyle(p.ink)
                        Text("CLICK A SLOT AROUND “THIS” TO PLACE YOUR OTHER MAC. PUSH THE CURSOR PAST THAT EDGE TO SWITCH.")
                            .font(WireFont.label(8)).foregroundStyle(p.faint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                WireCard(title: "PAIRING CODE", jp: "ペアリング", fig: "FIG. 3-2", p: p) {
                    if let s = state.config.flow.secret {
                        Text(s).font(WireFont.label(13, .bold)).foregroundStyle(p.ink).textSelection(.enabled)
                        HStack {
                            WireMiniButton(title: "COPY", p: p) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(s, forType: .string)
                            }
                            WireMiniButton(title: "NEW CODE", p: p) { state.config.flow.secret = FlowService.newSecret() }
                        }
                    } else {
                        WireMiniButton(title: "CREATE CODE", p: p) { state.config.flow.secret = FlowService.newSecret() }
                    }
                    HStack {
                        WireTextField(placeholder: "PASTE CODE FROM OTHER MAC", text: $entered, p: p)
                        WireMiniButton(title: "USE", p: p, enabled: entered.filter { $0.isLetter || $0.isNumber }.count >= 16) {
                            state.config.flow.secret = entered.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                            entered = ""
                        }
                    }
                }
                WireCard(title: "OPTIONS", jp: "設定", fig: "FIG. 3-3", p: p) {
                    WireCheck(label: "ONLY SWITCH WHILE HOLDING CONTROL", on: state.config.flow.requireControl, p: p) {
                        state.config.flow.requireControl.toggle()
                    }
                    WireCheck(label: "MX KEYS SWITCHES WITH THE MOUSE", on: state.config.flow.keyboardFollows, p: p) {
                        state.config.flow.keyboardFollows.toggle()
                    }
                    WireCheck(label: "SHARE CLIPBOARD", on: state.config.flow.clipboard, p: p) {
                        state.config.flow.clipboard.toggle()
                    }
                }
            }
            WireCard(title: "EASY-SWITCH CHANNELS", jp: "チャンネル", fig: "FIG. 3-4", p: p) {
                channelRow("THIS MAC", state.mouse?.host, state.keyboard?.host)
                channelRow((state.config.flow.peerName ?? "OTHER MAC").uppercased(),
                           state.config.flow.peerMouseHost, state.config.flow.peerKeyboardHost)
                Text("PAIR EACH DEVICE WITH EACH MAC ON A DIFFERENT CHANNEL. FLOW LEARNS THE OTHER MAC'S CHANNEL THE FIRST TIME THE MOUSE IS USED THERE.")
                    .font(WireFont.label(8)).foregroundStyle(p.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func channelRow(_ name: String, _ mouse: Int?, _ keyboard: Int?) -> some View {
        func s(_ v: Int?) -> String { v.map { "CH \($0 + 1)" } ?? "CH ?" }
        return HStack {
            Text(name).font(WireFont.label(9, .bold)).foregroundStyle(p.ink).frame(width: 160, alignment: .leading)
            Text("MOUSE \(s(mouse))").font(WireFont.label(9)).foregroundStyle(p.ink).frame(width: 110, alignment: .leading)
            Text("KEYS \(s(keyboard))").font(WireFont.label(9)).foregroundStyle(p.ink)
            Spacer()
        }
    }
}

/// "THIS" monitor in the middle with four slots around it; the chosen slot is the other Mac.
struct FlowEdgePicker: View {
    @Binding var edge: FlowEdge
    let enabled: Bool
    let peer: String?
    let p: WirePalette

    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let mw: CGFloat = 84, mh: CGFloat = 52, gap: CGFloat = 12
            ZStack {
                monitor("THIS", solid: true, highlighted: false).position(c)
                ForEach(FlowEdge.allCases) { e in
                    let off: CGPoint = {
                        switch e {
                        case .left: return CGPoint(x: -(mw + gap), y: 0)
                        case .right: return CGPoint(x: mw + gap, y: 0)
                        case .top: return CGPoint(x: 0, y: -(mh + gap + 6))
                        case .bottom: return CGPoint(x: 0, y: mh + gap + 6)
                        }
                    }()
                    Button { edge = e } label: {
                        monitor(e == edge ? (peer ?? "OTHER").uppercased() : "", solid: e == edge && enabled, highlighted: e == edge)
                    }
                    .buttonStyle(.plain)
                    .position(x: c.x + off.x, y: c.y + off.y)
                    .accessibilityLabel("Other Mac \(e.title)")
                    .accessibilityAddTraits(e == edge ? .isSelected : [])
                }
            }
        }
    }

    private func monitor(_ label: String, solid: Bool, highlighted: Bool) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Rectangle().strokeBorder(highlighted || solid ? p.ink : p.hairline,
                                         style: StrokeStyle(lineWidth: 1, dash: solid ? [] : [3, 2]))
                Rectangle().strokeBorder(p.hairline, lineWidth: 0.8).padding(4)
                Text(label).font(WireFont.label(8, .bold)).foregroundStyle(p.ink).lineLimit(1).padding(.horizontal, 6)
            }
            .frame(width: 84, height: 52)
            Rectangle().fill(highlighted || solid ? p.ink : p.hairline).frame(width: 22, height: 1)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - DEVICE tab

struct DeviceTab: View {
    @ObservedObject var state: AppState
    let p: WirePalette
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WireCard(title: "UNITS", jp: "装置", fig: "FIG. 4-1", p: p) {
                unit("MOUSE", state.mouse, placeholder: "MX MASTER 2S NOT CONNECTED")
                Rectangle().fill(p.hairline).frame(height: 1)
                unit("KEYS", state.keyboard, placeholder: "KEYBOARD NOT CONNECTED")
            }
            WireCard(title: "PERMISSIONS", jp: "権限", fig: "FIG. 4-2", p: p) {
                permission("ACCESSIBILITY — SEND SHORTCUTS, REMAP BUTTONS, FLOW", granted: state.accessibilityGranted,
                           anchor: "Privacy_Accessibility")
                permission("INPUT MONITORING — TALK TO THE MOUSE", granted: state.inputMonitoringGranted,
                           anchor: "Privacy_ListenEvent")
                if !state.inputMonitoringGranted {
                    WireMiniButton(title: "RELAUNCH AFTER GRANTING", p: p) { AppDelegate.relaunch() }
                }
            }
            HStack(alignment: .top, spacing: 16) {
                WireCard(title: "STARTUP", jp: "起動", fig: "FIG. 4-3", p: p) {
                    WireCheck(label: "OPEN LOGI LITE AT LOGIN", on: loginEnabled, p: p) {
                        do {
                            if loginEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
                            loginError = nil
                        } catch { loginError = error.localizedDescription }
                        loginEnabled = SMAppService.mainApp.status == .enabled
                    }
                    if let e = loginError { Text(e.uppercased()).font(WireFont.label(8)).foregroundStyle(p.ink) }
                }
                WireCard(title: "DATA", jp: "データ", fig: "FIG. 4-4", p: p) {
                    Text(ConfigStore.file.path).font(WireFont.label(8)).foregroundStyle(p.faint).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    WireMiniButton(title: "RESET TO IMPORTED LOGI OPTIONS SETUP", p: p) { state.config = Config.initial() }
                }
            }
            if state.logiOptionsRunning {
                WireCard(title: "LOGI OPTIONS DETECTED", jp: "競合", p: p) {
                    Text("IT COMPETES WITH LOGI LITE FOR THE MOUSE BUTTONS. QUIT OR UNINSTALL IT.")
                        .font(WireFont.label(9)).foregroundStyle(p.ink)
                    WireMiniButton(title: "STOP LOGI OPTIONS NOW", p: p) { AppDelegate.quitLogiOptions() }
                }
            }
        }
    }

    @ViewBuilder private func unit(_ label: String, _ d: DeviceSnapshot?, placeholder: String) -> some View {
        if let d {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(d.name.uppercased()).font(WireFont.label(11, .bold)).foregroundStyle(p.ink)
                    Spacer()
                    Text(d.host.map { "CHANNEL \($0 + 1) OF \(d.hostCount ?? 3)" } ?? "CHANNEL ?")
                        .font(WireFont.label(8)).foregroundStyle(p.faint)
                }
                CellGauge(label: label, device: d, p: p, cells: 20)
            }
        } else {
            Text(placeholder).font(WireFont.label(9, .bold)).foregroundStyle(p.faint)
        }
    }

    private func permission(_ title: String, granted: Bool, anchor: String) -> some View {
        HStack(spacing: 8) {
            Text(granted ? "✓" : "!").font(WireFont.label(9, .bold)).foregroundStyle(granted ? p.paper : p.ink)
                .frame(width: 15, height: 15)
                .background(granted ? p.ink : .clear)
                .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
            Text(title).font(WireFont.label(9)).foregroundStyle(p.ink)
            Spacer()
            if !granted {
                WireMiniButton(title: "OPEN SETTINGS", p: p) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
                }
            }
        }
    }
}
