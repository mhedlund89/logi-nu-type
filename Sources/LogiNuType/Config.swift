import Foundation
import CoreGraphics

enum ButtonID: String, Codable, CaseIterable, Identifiable {
    case gesture, wheelMode, back, forward, middle
    var id: String { rawValue }

    var cid: UInt16 {
        switch self {
        case .gesture: return ControlID.gesture
        case .wheelMode: return ControlID.wheelMode
        case .back: return ControlID.back
        case .forward: return ControlID.forward
        case .middle: return ControlID.middle
        }
    }

    init?(cid: UInt16) {
        guard let match = ButtonID.allCases.first(where: { $0.cid == cid }) else { return nil }
        self = match
    }

    var title: String {
        switch self {
        case .gesture: return "Thumb (gesture) button"
        case .wheelMode: return "Button behind wheel"
        case .back: return "Back button"
        case .forward: return "Forward button"
        case .middle: return "Middle click"
        }
    }
}

enum GestureDirection: String, Codable, CaseIterable, Identifiable {
    case click, up, down, left, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .click: return "Click (no movement)"
        case .up: return "Hold + move up"
        case .down: return "Hold + move down"
        case .left: return "Hold + move left"
        case .right: return "Hold + move right"
        }
    }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case passthrough, nothing
    case missionControl, appExpose, showDesktop, launchpad, desktopLeft, desktopRight
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, mute
    case browserBack, browserForward, middleClick
    case copy, paste, undo, redo, screenshot
    case toggleWheelMode
    case brightnessUp, brightnessDown, lockScreen, calculator, contextMenu, eject
    case keystroke, openApp, openURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passthrough: return "Default (native)"
        case .nothing: return "Do nothing"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Apps (Launchpad)"
        case .desktopLeft: return "Desktop to the left"
        case .desktopRight: return "Desktop to the right"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .browserBack: return "Back"
        case .browserForward: return "Forward"
        case .middleClick: return "Middle click"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .screenshot: return "Screenshot (area)"
        case .toggleWheelMode: return "Toggle wheel ratchet / free spin"
        case .brightnessUp: return "Brightness up"
        case .brightnessDown: return "Brightness down"
        case .lockScreen: return "Lock screen"
        case .calculator: return "Calculator"
        case .contextMenu: return "Right-click menu"
        case .eject: return "Eject"
        case .keystroke: return "Keyboard shortcut…"
        case .openApp: return "Open app…"
        case .openURL: return "Open website…"
        }
    }
}

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64   // CGEventFlags raw value (device-independent bits only)
    var display: String
}

struct Action: Codable, Hashable {
    var kind: ActionKind
    var keys: KeyCombo?
    var path: String?
    var url: String?

    init(_ kind: ActionKind, keys: KeyCombo? = nil, path: String? = nil, url: String? = nil) {
        self.kind = kind; self.keys = keys; self.path = path; self.url = url
    }

    var summary: String {
        switch kind {
        case .keystroke: return keys?.display ?? "Shortcut (not set)"
        case .openApp: return path.map { "Open " + URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "Open app (not set)"
        case .openURL: return url ?? "Open website (not set)"
        default: return kind.title
        }
    }
}

struct ButtonConfig: Codable, Hashable {
    var action: Action
    var useGestures: Bool = false
    var gestures: [String: Action] = [:]

    func gesture(_ d: GestureDirection) -> Action { gestures[d.rawValue] ?? Action(.nothing) }
}

enum ThumbWheelAction: String, Codable, CaseIterable, Identifiable {
    case horizontalScroll, volume, zoom, tabs, desktops, nothing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .horizontalScroll: return "Horizontal scroll"
        case .volume: return "Volume"
        case .zoom: return "Zoom"
        case .tabs: return "Switch tabs"
        case .desktops: return "Switch desktops"
        case .nothing: return "Do nothing"
        }
    }
}

struct Profile: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var bundleID: String?          // nil = "All apps" default profile
    var appPath: String?
    var buttons: [String: ButtonConfig] = [:]
    var thumbWheel: ThumbWheelAction?
    /// MX Keys programmable keys, by control ID ("0x00E5"). Optional so older config files still load.
    var keys: [String: Action]?

    func button(_ b: ButtonID) -> ButtonConfig? { buttons[b.rawValue] }
    func key(_ cid: UInt16) -> Action? { keys?[KeyboardKey.configKey(cid)] }
    mutating func setKey(_ cid: UInt16, _ a: Action?) {
        var k = keys ?? [:]
        k[KeyboardKey.configKey(cid)] = a
        keys = k.isEmpty ? nil : k
    }
}

/// A programmable MX Keys key: its HID++ control ID, name, and what it does natively.
struct KeyboardKey: Identifiable, Hashable {
    let cid: UInt16
    let name: String
    let native: ActionKind
    var id: UInt16 { cid }

    static func configKey(_ cid: UInt16) -> String { String(format: "0x%04X", cid) }

    /// Keys the MX Keys reports as divertable (names from the HID++ control table). The backlight and Easy-Switch
    /// keys are left to the keyboard: their native behaviour can't be reproduced once they are diverted.
    static let all: [KeyboardKey] = [
        KeyboardKey(cid: 0x00C7, name: "Brightness down", native: .brightnessDown),
        KeyboardKey(cid: 0x00C8, name: "Brightness up", native: .brightnessUp),
        KeyboardKey(cid: 0x00E0, name: "Mission Control", native: .missionControl),
        KeyboardKey(cid: 0x00E1, name: "Launchpad", native: .launchpad),
        KeyboardKey(cid: 0x00E4, name: "Previous track", native: .previousTrack),
        KeyboardKey(cid: 0x00E5, name: "Play / Pause", native: .playPause),
        KeyboardKey(cid: 0x00E6, name: "Next track", native: .nextTrack),
        KeyboardKey(cid: 0x00E7, name: "Mute", native: .mute),
        KeyboardKey(cid: 0x00E8, name: "Volume down", native: .volumeDown),
        KeyboardKey(cid: 0x00E9, name: "Volume up", native: .volumeUp),
        KeyboardKey(cid: 0x000A, name: "Calculator", native: .calculator),
        KeyboardKey(cid: 0x00BF, name: "Screenshot", native: .screenshot),
        KeyboardKey(cid: 0x00EA, name: "Right-click menu", native: .contextMenu),
        KeyboardKey(cid: 0x006F, name: "Lock", native: .lockScreen),
        KeyboardKey(cid: 0x000D, name: "Eject", native: .eject),
    ]
    static func named(_ cid: UInt16) -> KeyboardKey? { all.first { $0.cid == cid } }
}

enum FlowEdge: String, Codable, CaseIterable, Identifiable {
    case left, right, top, bottom
    var id: String { rawValue }
    var opposite: FlowEdge {
        switch self { case .left: return .right; case .right: return .left; case .top: return .bottom; case .bottom: return .top }
    }
    var title: String {
        switch self {
        case .left: return "Left of this Mac"
        case .right: return "Right of this Mac"
        case .top: return "Above this Mac"
        case .bottom: return "Below this Mac"
        }
    }
}

/// Decode helper: a missing or unreadable field keeps its default instead of failing the whole settings file.
extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default d: T) -> T { ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? d }
}

struct FlowConfig: Codable, Hashable {
    var enabled = false
    var secret: String?
    var otherMacEdge: FlowEdge = .left
    var requireControl = false
    var keyboardFollows = true
    var clipboard = true
    /// Easy-Switch slots the other Mac uses, learned from it over the network.
    var peerName: String?
    var peerMouseHost: Int?
    var peerKeyboardHost: Int?

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FlowConfig()
        enabled = c.value(.enabled, default: d.enabled)
        secret = c.value(.secret, default: d.secret)
        otherMacEdge = c.value(.otherMacEdge, default: d.otherMacEdge)
        requireControl = c.value(.requireControl, default: d.requireControl)
        keyboardFollows = c.value(.keyboardFollows, default: d.keyboardFollows)
        clipboard = c.value(.clipboard, default: d.clipboard)
        peerName = c.value(.peerName, default: d.peerName)
        peerMouseHost = c.value(.peerMouseHost, default: d.peerMouseHost)
        peerKeyboardHost = c.value(.peerKeyboardHost, default: d.peerKeyboardHost)
    }
}

struct PointerConfig: Codable, Hashable {
    var dpi: Int?
    var smartShift = false
    var smartShiftThreshold = 16
    var reverseWheel = false
    var reverseThumbWheel = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PointerConfig()
        dpi = c.value(.dpi, default: d.dpi)
        smartShift = c.value(.smartShift, default: d.smartShift)
        smartShiftThreshold = c.value(.smartShiftThreshold, default: d.smartShiftThreshold)
        reverseWheel = c.value(.reverseWheel, default: d.reverseWheel)
        reverseThumbWheel = c.value(.reverseThumbWheel, default: d.reverseThumbWheel)
    }
}

struct Config: Codable, Hashable {
    var defaults: Profile
    var apps: [Profile]
    var pointer = PointerConfig()
    var flow = FlowConfig()

    init(defaults: Profile, apps: [Profile], pointer: PointerConfig = PointerConfig(), flow: FlowConfig = FlowConfig()) {
        self.defaults = defaults; self.apps = apps; self.pointer = pointer; self.flow = flow
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaults = try c.decode(Profile.self, forKey: .defaults)
        apps = c.value(.apps, default: [])
        pointer = c.value(.pointer, default: PointerConfig())
        flow = c.value(.flow, default: FlowConfig())
    }

    func profile(for bundleID: String?) -> Profile? {
        guard let bundleID else { return nil }
        return apps.first { $0.bundleID == bundleID }
    }

    func effectiveButton(_ b: ButtonID, bundleID: String?) -> ButtonConfig {
        profile(for: bundleID)?.button(b) ?? defaults.button(b) ?? ButtonConfig(action: Action(.passthrough))
    }

    func effectiveKey(_ cid: UInt16, bundleID: String?) -> Action {
        profile(for: bundleID)?.key(cid) ?? defaults.key(cid) ?? Action(.passthrough)
    }

    func effectiveThumbWheel(bundleID: String?) -> ThumbWheelAction {
        profile(for: bundleID)?.thumbWheel ?? defaults.thumbWheel ?? .horizontalScroll
    }

    /// Starting point: Logi Options defaults plus the customisations found in its settings on this Mac.
    static func initial() -> Config {
        let cmd = CGEventFlags.maskCommand.rawValue
        let opt = CGEventFlags.maskAlternate.rawValue

        var all = Profile(name: "All apps")
        all.buttons = [
            ButtonID.gesture.rawValue: ButtonConfig(
                action: Action(.missionControl), useGestures: true,
                gestures: [
                    GestureDirection.click.rawValue: Action(.missionControl),
                    GestureDirection.up.rawValue: Action(.missionControl),
                    GestureDirection.down.rawValue: Action(.appExpose),
                    GestureDirection.left.rawValue: Action(.desktopLeft),
                    GestureDirection.right.rawValue: Action(.desktopRight),
                ]),
            ButtonID.wheelMode.rawValue: ButtonConfig(action: Action(.passthrough)),
            ButtonID.back.rawValue: ButtonConfig(action: Action(.passthrough)),
            ButtonID.forward.rawValue: ButtonConfig(action: Action(.passthrough)),
            ButtonID.middle.rawValue: ButtonConfig(action: Action(.passthrough)),
        ]
        all.thumbWheel = .horizontalScroll

        var chrome = Profile(name: "Google Chrome", bundleID: "com.google.Chrome", appPath: "/Applications/Google Chrome.app")
        chrome.buttons[ButtonID.wheelMode.rawValue] = ButtonConfig(
            action: Action(.keystroke, keys: KeyCombo(keyCode: 0x11, modifiers: cmd, display: "⌘T")))

        var sublime = Profile(name: "Sublime Text", bundleID: "com.sublimetext.4", appPath: "/Applications/Sublime Text.app")
        sublime.buttons[ButtonID.wheelMode.rawValue] = ButtonConfig(
            action: Action(.keystroke, keys: KeyCombo(keyCode: 0x03, modifiers: cmd | opt, display: "⌥⌘F")))

        var spotify = Profile(name: "Spotify", bundleID: "com.spotify.client", appPath: "/Applications/Spotify.app")
        spotify.buttons[ButtonID.wheelMode.rawValue] = ButtonConfig(action: Action(.playPause))
        spotify.thumbWheel = .volume

        var figma = Profile(name: "Figma", bundleID: "com.figma.Desktop", appPath: "/Applications/Figma.app")
        figma.thumbWheel = .zoom

        return Config(defaults: all, apps: [chrome, sublime, spotify, figma])
    }
}

enum ConfigStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LogiNuType", isDirectory: true)
        // One-time move of settings saved before the rename to Logi : nu-type.
        let old = base.appendingPathComponent("LogiLite", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path), fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: dir) }
        return dir
    }
    static var file: URL { directory.appendingPathComponent("config.json") }

    static func load() -> Config {
        if let data = try? Data(contentsOf: file), let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        if FileManager.default.fileExists(atPath: file.path) {
            // Unreadable (e.g. from a newer version): keep a copy rather than silently losing it.
            let backup = directory.appendingPathComponent("config-\(Int(Date().timeIntervalSince1970)).json.bak")
            try? FileManager.default.copyItem(at: file, to: backup)
        }
        let cfg = Config.initial()
        save(cfg)
        return cfg
    }

    static func save(_ cfg: Config) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) { try? data.write(to: file, options: .atomic) }
    }
}
