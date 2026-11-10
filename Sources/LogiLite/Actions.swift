import AppKit
import CoreGraphics

enum ActionRunner {
    private static let source = CGEventSource(stateID: .hidSystemState)
    /// Tagged on every event we post so our own event tap lets it through untouched.
    static let syntheticMarker: Int64 = 0x4C4C_4954 // "LLIT"

    /// Perform an action on button press. Mouse-button actions are split into down/up so drags work.
    static func press(_ action: Action, mouse: MouseController?) {
        Log.info("action \(action.kind.rawValue) axTrusted=\(AXIsProcessTrusted())")
        switch action.kind {
        case .passthrough, .nothing: break
        case .missionControl: dock("com.apple.expose.awake", fallbackArg: nil)
        case .appExpose: dock("com.apple.expose.front.awake", fallbackArg: "2")
        case .showDesktop: dock("com.apple.showdesktop.awake", fallbackArg: "1")
        case .launchpad: NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Apps.app"))
        case .desktopLeft: key(0x7B, [.maskControl, .maskSecondaryFn, .maskNumericPad])
        case .desktopRight: key(0x7C, [.maskControl, .maskSecondaryFn, .maskNumericPad])
        case .playPause: mediaKey(16)
        case .nextTrack: mediaKey(17)
        case .previousTrack: mediaKey(18)
        case .volumeUp: mediaKey(0)
        case .volumeDown: mediaKey(1)
        case .mute: mediaKey(7)
        case .browserBack: mouseButton(3, down: true)
        case .browserForward: mouseButton(4, down: true)
        case .middleClick: mouseButton(2, down: true)
        case .copy: key(0x08, .maskCommand)
        case .paste: key(0x09, .maskCommand)
        case .undo: key(0x06, .maskCommand)
        case .redo: key(0x06, [.maskCommand, .maskShift])
        case .screenshot: key(0x15, [.maskCommand, .maskShift])
        case .toggleWheelMode: mouse?.toggleWheelMode()
        case .keystroke:
            if let k = action.keys { key(CGKeyCode(k.keyCode), CGEventFlags(rawValue: k.modifiers)) }
        case .openApp:
            if let p = action.path {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: p), configuration: .init())
            }
        case .openURL:
            if let s = action.url, let u = URL(string: s.contains("://") ? s : "https://" + s) {
                NSWorkspace.shared.open(u)
            }
        }
    }

    static func release(_ action: Action) {
        switch action.kind {
        case .browserBack: mouseButton(3, down: false)
        case .browserForward: mouseButton(4, down: false)
        case .middleClick: mouseButton(2, down: false)
        default: break
        }
    }

    /// The native behaviour of a button, used when it is diverted but set to "Default".
    static func nativeAction(for button: ButtonID) -> Action {
        switch button {
        case .back: return Action(.browserBack)
        case .forward: return Action(.browserForward)
        case .middle: return Action(.middleClick)
        case .wheelMode: return Action(.toggleWheelMode)
        case .gesture: return Action(.nothing)
        }
    }

    // MARK: Primitives

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (key << 16) | ((down ? 0xA : 0xB) << 8)
            let e = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                       timestamp: 0, windowNumber: 0, context: nil,
                                       subtype: 8, data1: data1, data2: -1)
            e?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func mouseButton(_ button: Int, down: Bool) {
        let loc = CGEvent(source: nil)?.location ?? .zero
        let type: CGEventType = down ? .otherMouseDown : .otherMouseUp
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: loc,
                              mouseButton: CGMouseButton(rawValue: UInt32(button)) ?? .center) else { return }
        e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    private typealias CoreDockSendNotification = @convention(c) (CFString, Int32) -> Void
    private static let coreDock: CoreDockSendNotification? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let sym = dlsym(h, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: CoreDockSendNotification.self)
    }()

    private static func dock(_ notification: String, fallbackArg: String?) {
        if let fn = coreDock {
            fn(notification as CFString, 0)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
        if let a = fallbackArg { p.arguments = [a] }
        try? p.run()
    }
}
