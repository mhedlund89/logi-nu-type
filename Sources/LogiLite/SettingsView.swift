import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var state: AppState
    let engine: Engine

    var body: some View {
        TabView {
            ButtonsTab(state: state).tabItem { Label("Buttons", systemImage: "computermouse") }
            PointerTab(state: state, engine: engine).tabItem { Label("Point & Scroll", systemImage: "scroll") }
            FlowTab(state: state).tabItem { Label("Flow", systemImage: "display.2") }
            GeneralTab(state: state).tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding(12)
        .frame(minWidth: 720, minHeight: 600)
    }
}

// MARK: - Buttons

struct ButtonsTab: View {
    @ObservedObject var state: AppState
    @State private var selection: UUID?

    private var selectedID: UUID { selection ?? state.config.defaults.id }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                List(selection: $selection) {
                    Label("All apps", systemImage: "square.grid.2x2").tag(state.config.defaults.id as UUID?)
                    Section("App-specific") {
                        ForEach(state.config.apps) { p in
                            Label(p.name, systemImage: "app").tag(p.id as UUID?)
                        }
                    }
                }
                HStack {
                    Button { addApp() } label: { Image(systemName: "plus") }
                    Button { removeSelected() } label: { Image(systemName: "minus") }
                        .disabled(selectedID == state.config.defaults.id)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 200)
            Divider()
            ProfileEditor(profile: profileBinding(selectedID),
                          isDefault: selectedID == state.config.defaults.id,
                          defaults: state.config.defaults)
                .id(selectedID)
        }
    }

    private func profileBinding(_ id: UUID) -> Binding<Profile> {
        Binding(
            get: {
                if id == state.config.defaults.id { return state.config.defaults }
                return state.config.apps.first { $0.id == id } ?? state.config.defaults
            },
            set: { p in
                if p.id == state.config.defaults.id { state.config.defaults = p }
                else if let i = state.config.apps.firstIndex(where: { $0.id == p.id }) { state.config.apps[i] = p }
            })
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        if let existing = state.config.apps.first(where: { $0.bundleID == id }) { selection = existing.id; return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        let p = Profile(name: name, bundleID: id, appPath: url.path)
        state.config.apps.append(p)
        selection = p.id
    }

    private func removeSelected() {
        state.config.apps.removeAll { $0.id == selectedID }
        selection = state.config.defaults.id
    }
}

struct ProfileEditor: View {
    @Binding var profile: Profile
    let isDefault: Bool
    let defaults: Profile

    var body: some View {
        Form {
            Section {
                ForEach(ButtonID.allCases) { b in
                    ButtonEditor(button: b, isDefault: isDefault,
                                 config: Binding(get: { profile.buttons[b.rawValue] },
                                                 set: { profile.buttons[b.rawValue] = $0 }),
                                 fallback: defaults.button(b) ?? ButtonConfig(action: Action(.passthrough)))
                }
            } header: {
                Text(isDefault ? "Buttons — every app" : "Buttons — \(profile.name)")
            }
            Section("Thumb wheel") {
                Picker("Thumb wheel", selection: Binding(
                    get: { profile.thumbWheel },
                    set: { profile.thumbWheel = $0 })) {
                    if !isDefault { Text("Same as All apps (\((defaults.thumbWheel ?? .horizontalScroll).title))").tag(ThumbWheelAction?.none) }
                    ForEach(ThumbWheelAction.allCases) { Text($0.title).tag(ThumbWheelAction?.some($0)) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ButtonEditor: View {
    let button: ButtonID
    let isDefault: Bool
    @Binding var config: ButtonConfig?
    let fallback: ButtonConfig

    private var inherits: Bool { !isDefault && config == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(button.title).fontWeight(.semibold)
                Spacer()
                if !isDefault {
                    Toggle("Same as All apps", isOn: Binding(
                        get: { config == nil },
                        set: { config = $0 ? nil : fallback }))
                    .toggleStyle(.checkbox)
                }
            }
            if inherits {
                Text(describe(fallback)).foregroundStyle(.secondary).font(.callout)
            } else {
                let cfg = Binding<ButtonConfig>(get: { config ?? fallback }, set: { config = $0 })
                Toggle("Hold and move for gestures", isOn: cfg.useGestures)
                if cfg.wrappedValue.useGestures {
                    ForEach(GestureDirection.allCases) { d in
                        ActionEditor(label: d.title, action: Binding(
                            get: { cfg.wrappedValue.gesture(d) },
                            set: { cfg.wrappedValue.gestures[d.rawValue] = $0 }))
                    }
                } else {
                    ActionEditor(label: "Action", action: cfg.action)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func describe(_ c: ButtonConfig) -> String {
        if c.useGestures {
            return "Gestures: " + GestureDirection.allCases.map { "\($0.rawValue) → \(c.gesture($0).summary)" }.joined(separator: ", ")
        }
        return c.action.summary
    }
}

struct ActionEditor: View {
    let label: String
    @Binding var action: Action

    var body: some View {
        HStack {
            Picker(label, selection: $action.kind) {
                ForEach(ActionKind.allCases) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 380)
            switch action.kind {
            case .keystroke:
                KeyRecorder(combo: $action.keys)
            case .openApp:
                Button(action.path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "Choose app…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    if panel.runModal() == .OK { action.path = panel.url?.path }
                }
            case .openURL:
                TextField("https://…", text: Binding(get: { action.url ?? "" }, set: { action.url = $0 }))
                    .frame(width: 200)
            default:
                EmptyView()
            }
        }
    }
}

struct KeyRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press shortcut… (Esc cancels)" : (combo?.display ?? "Record shortcut")) {
            recording ? stop() : start()
        }
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

// MARK: - Point & Scroll

struct PointerTab: View {
    @ObservedObject var state: AppState
    let engine: Engine
    @State private var dpi: Double = 1000

    var body: some View {
        Form {
            Section("Pointer speed") {
                if state.mouse != nil {
                    HStack {
                        Slider(value: $dpi, in: 200...4000, step: 50) { editing in
                            if !editing { engine.setDPI(Int(dpi)) }
                        }
                        Text("\(Int(dpi)) DPI").monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                    Text("macOS's own Tracking Speed setting still applies on top of this.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Mouse not connected").foregroundStyle(.secondary)
                }
            }
            Section("Scroll wheel") {
                HStack {
                    Text("Wheel mode: \(state.freeSpin == nil ? "unknown" : (state.freeSpin! ? "Free spin" : "Ratchet"))")
                    Spacer()
                    Button("Switch") { engine.devices.mouse?.toggleWheelMode() }.disabled(state.mouse == nil)
                }
                Toggle("SmartShift (flick the wheel to free-spin automatically)", isOn: $state.config.pointer.smartShift)
                if state.config.pointer.smartShift {
                    HStack {
                        Text("Sensitivity")
                        Slider(value: Binding(get: { Double(state.config.pointer.smartShiftThreshold) },
                                              set: { state.config.pointer.smartShiftThreshold = Int($0) }), in: 1...50, step: 1)
                        Text("\(state.config.pointer.smartShiftThreshold)").monospacedDigit().frame(width: 30)
                    }
                }
                Toggle("Reverse scroll direction (this mouse only)", isOn: $state.config.pointer.reverseWheel)
                Toggle("Reverse thumb wheel direction", isOn: $state.config.pointer.reverseThumbWheel)
            }
        }
        .formStyle(.grouped)
        .onAppear { dpi = Double(state.dpi ?? state.config.pointer.dpi ?? 1000) }
        .onChange(of: state.dpi) { _, new in if let new { dpi = Double(new) } }
    }
}

// MARK: - Flow

struct FlowTab: View {
    @ObservedObject var state: AppState
    @State private var entered = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable Flow", isOn: Binding(
                    get: { state.config.flow.enabled },
                    set: { on in
                        if on && state.config.flow.secret == nil { state.config.flow.secret = FlowService.newSecret() }
                        state.config.flow.enabled = on
                    }))
                LabeledContent("Status", value: state.flowStatus)
            } footer: {
                Text("Install Logi Lite on your other Mac too. Both Macs need to be on the same network and use the same pairing code.")
            }

            Section("Pairing code") {
                if let s = state.config.flow.secret {
                    HStack {
                        Text(s).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(s, forType: .string)
                        }
                        Button("New code") { state.config.flow.secret = FlowService.newSecret() }
                    }
                }
                HStack {
                    TextField("Paste the code from your other Mac", text: $entered)
                    Button("Use this code") {
                        let code = entered.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        guard code.filter({ $0.isLetter || $0.isNumber }).count >= 16 else { return }
                        state.config.flow.secret = code
                        entered = ""
                    }
                }
            }

            Section("Layout") {
                Picker("Your other Mac is", selection: $state.config.flow.otherMacEdge) {
                    ForEach(FlowEdge.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Only switch while holding Control", isOn: $state.config.flow.requireControl)
                Toggle("MX Keys switches along with the mouse", isOn: $state.config.flow.keyboardFollows)
                Toggle("Share clipboard between Macs", isOn: $state.config.flow.clipboard)
            }

            Section("Easy-Switch channels") {
                LabeledContent("This Mac", value: channels(state.mouse?.host, state.keyboard?.host))
                LabeledContent(state.config.flow.peerName ?? "Other Mac",
                               value: channels(state.config.flow.peerMouseHost, state.config.flow.peerKeyboardHost))
                Text("Pair the mouse and keyboard with each Mac on a different channel (the buttons on the devices). Flow learns the other Mac's channel the first time the mouse is used there while both Macs are running Logi Lite.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func channels(_ mouse: Int?, _ keyboard: Int?) -> String {
        func s(_ v: Int?) -> String { v.map { "\($0 + 1)" } ?? "?" }
        return "mouse \(s(mouse)), keyboard \(s(keyboard))"
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject var state: AppState
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Devices") {
                device(state.mouse, placeholder: "MX Master 2S not connected")
                device(state.keyboard, placeholder: "Keyboard not connected")
            }
            Section("Permissions") {
                permission("Accessibility (send shortcuts, scroll changes, Flow)", granted: state.accessibilityGranted,
                           url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                permission("Input Monitoring (talk to the mouse)", granted: state.inputMonitoringGranted,
                           url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                if !state.inputMonitoringGranted {
                    Button("Relaunch Logi Lite after granting") { AppDelegate.relaunch() }
                }
            }
            Section("Startup") {
                Toggle("Open Logi Lite at login", isOn: Binding(get: { loginEnabled }, set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch { loginError = error.localizedDescription }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                }))
                if let e = loginError { Text(e).font(.caption).foregroundStyle(.red) }
            }
            if state.logiOptionsRunning {
                Section("Logi Options") {
                    Text("Logi Options is still running. It fights Logi Lite for the mouse buttons. Quit or uninstall it.")
                    Button("Quit Logi Options now") { AppDelegate.quitLogiOptions() }
                }
            }
            Section("Settings file") {
                Text(ConfigStore.file.path).font(.caption).textSelection(.enabled)
                Button("Reset to the imported Logi Options setup") { state.config = Config.initial() }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func device(_ d: DeviceSnapshot?, placeholder: String) -> some View {
        if let d {
            LabeledContent(d.name, value: d.battery.map { "\($0)%" + (d.charging ? " (charging)" : "") } ?? "battery unknown")
        } else {
            Text(placeholder).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func permission(_ title: String, granted: Bool, url: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
            Spacer()
            if !granted { Button("Open Settings") { NSWorkspace.shared.open(URL(string: url)!) } }
        }
    }
}
