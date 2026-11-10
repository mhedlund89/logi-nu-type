import AppKit
import Combine
import CoreGraphics

struct DeviceSnapshot: Equatable {
    var name: String
    var battery: Int?
    var charging: Bool
    var host: Int?
    var hostCount: Int?
}

/// Observable state shared by the menu and the settings window.
final class AppState: ObservableObject {
    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            ConfigStore.save(config)
            onConfigChanged?(oldValue, config)
        }
    }
    @Published var frontBundleID: String?
    @Published var mouse: DeviceSnapshot?
    @Published var keyboard: DeviceSnapshot?
    @Published var dpi: Int?
    @Published var freeSpin: Bool?
    @Published var flowStatus = "Off"
    @Published var accessibilityGranted = false
    @Published var inputMonitoringGranted = false
    @Published var logiOptionsRunning = false

    var onConfigChanged: ((Config, Config) -> Void)?

    init() { config = ConfigStore.load() }
}

/// Global event tap for scroll wheel and pointer movement.
final class EventTap {
    var handler: ((CGEventType, CGEvent) -> CGEvent?)?
    private var tap: CFMachPort?

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let out = me.handler?(type, event) else { return nil }
            return Unmanaged.passUnretained(out)
        }, userInfo: ctx) else { return false }
        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
}

final class Engine {
    let state: AppState
    let devices = DeviceManager()
    lazy var flow = FlowService(state: state, devices: devices)
    private let tap = EventTap()

    private struct GestureTrack { var dx = 0; var dy = 0; var fired = false; let config: ButtonConfig }
    private var gestures: [UInt16: GestureTrack] = [:]
    private var held: [UInt16: Action] = [:]
    private var thumbAccumulator = 0.0
    private var lastDesktopSwitch = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private static let gestureThreshold = 50.0

    init(state: AppState) { self.state = state }

    func start() {
        state.frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.state.frontBundleID = app?.bundleIdentifier
            self?.applyDiversion()
        })

        devices.onMouseAttached = { [weak self] m in
            guard let self else { return }
            m.onButton = { [weak self] cid, down in self?.button(cid, down: down) }
            m.onMovement = { [weak self] dx, dy in self?.movement(dx, dy) }
            self.gestures.removeAll()
            self.held.removeAll()
            self.applyDiversion()
            self.applySmartShift()
            if let dpi = self.state.config.pointer.dpi { m.setDPI(dpi) }
        }
        devices.onChange = { [weak self] in self?.publishDevices() }
        devices.start()

        state.onConfigChanged = { [weak self] old, new in
            guard let self else { return }
            self.applyDiversion()
            if old.pointer.smartShift != new.pointer.smartShift || old.pointer.smartShiftThreshold != new.pointer.smartShiftThreshold {
                self.applySmartShift()
            }
            if old.flow != new.flow { self.flow.configure() }
        }

        tap.handler = { [weak self] type, event in self?.handle(type, event) ?? event }
        startTapWhenPermitted()

        // Battery changes are pushed by the device, but poll occasionally as a fallback.
        Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.devices.mouse?.refreshBattery()
            self?.devices.keyboard?.refreshBattery()
        }
        flow.configure()
    }

    func stop() {
        devices.mouse?.restoreNativeButtons()
    }

    private func startTapWhenPermitted() {
        if tap.start() { state.accessibilityGranted = true; return }
        state.accessibilityGranted = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startTapWhenPermitted() }
    }

    private func publishDevices() {
        func snap(_ d: LogiDevice?) -> DeviceSnapshot? {
            d.map { DeviceSnapshot(name: $0.name, battery: $0.battery, charging: $0.charging, host: $0.hostIndex, hostCount: $0.hostCount) }
        }
        state.mouse = snap(devices.mouse)
        state.keyboard = snap(devices.keyboard)
        state.dpi = devices.mouse?.dpi
        state.freeSpin = devices.mouse?.freeSpin
        flow.devicesChanged()
    }

    // MARK: Device settings

    func applyDiversion() {
        guard let m = devices.mouse else { return }
        var wanted: [UInt16: DiversionMode] = [:]
        for b in ButtonID.allCases {
            let cfg = state.config.effectiveButton(b, bundleID: state.frontBundleID)
            if cfg.useGestures { wanted[b.cid] = .divertWithMovement }
            else if cfg.action.kind != .passthrough { wanted[b.cid] = .divert }
        }
        m.setDiversion(wanted)
    }

    func applySmartShift() {
        let p = state.config.pointer
        devices.mouse?.setSmartShift(enabled: p.smartShift, threshold: p.smartShiftThreshold)
    }

    func setDPI(_ dpi: Int) {
        state.config.pointer.dpi = dpi
        devices.mouse?.setDPI(dpi)
    }

    // MARK: Buttons and gestures

    private func resolved(_ a: Action, _ b: ButtonID) -> Action {
        a.kind == .passthrough ? ActionRunner.nativeAction(for: b) : a
    }

    private func button(_ cid: UInt16, down: Bool) {
        guard let b = ButtonID(cid: cid) else { return }
        if down {
            let cfg = state.config.effectiveButton(b, bundleID: state.frontBundleID)
            if cfg.useGestures {
                gestures[cid] = GestureTrack(config: cfg)
            } else {
                let a = resolved(cfg.action, b)
                held[cid] = a
                ActionRunner.press(a, mouse: devices.mouse)
            }
        } else {
            if let g = gestures.removeValue(forKey: cid) {
                if !g.fired { fire(resolved(g.config.gesture(.click), b)) }
            } else if let a = held.removeValue(forKey: cid) {
                ActionRunner.release(a)
            }
        }
    }

    private func movement(_ dx: Int, _ dy: Int) {
        for (cid, var g) in gestures where !g.fired {
            g.dx += dx
            g.dy += dy
            if hypot(Double(g.dx), Double(g.dy)) >= Self.gestureThreshold, let b = ButtonID(cid: cid) {
                g.fired = true
                let dir: GestureDirection = abs(g.dx) > abs(g.dy) ? (g.dx > 0 ? .right : .left) : (g.dy > 0 ? .down : .up)
                fire(resolved(g.config.gesture(dir), b))
            }
            gestures[cid] = g
        }
    }

    private func fire(_ a: Action) {
        ActionRunner.press(a, mouse: devices.mouse)
        ActionRunner.release(a)
    }

    // MARK: Event tap

    private func handle(_ type: CGEventType, _ e: CGEvent) -> CGEvent? {
        if type == .scrollWheel { return scroll(e) }
        flow.pointerMoved(e, isDrag: type != .mouseMoved)
        return e
    }

    private func scroll(_ e: CGEvent) -> CGEvent? {
        // Trackpads and Magic Mouse report scroll phases; a wheel mouse does not.
        let phase = e.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentum = e.getIntegerValueField(.scrollWheelEventMomentumPhase)
        guard phase == 0, momentum == 0 else { return e }

        let p = state.config.pointer
        let vLine = e.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let vPoint = e.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let hLine = e.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let hPoint = e.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)

        if p.reverseWheel, vLine != 0 || vPoint != 0 { negate(e, axis: 1) }

        guard (hLine != 0 || hPoint != 0), vLine == 0, vPoint == 0 else { return e }
        let thumb = state.config.effectiveThumbWheel(bundleID: state.frontBundleID)
        switch thumb {
        case .horizontalScroll:
            if p.reverseThumbWheel { negate(e, axis: 2) }
            return e
        case .nothing:
            return nil
        default:
            var steps = 0
            if hLine != 0 {
                steps = Int(hLine)
            } else {
                thumbAccumulator += hPoint
                if abs(thumbAccumulator) >= 10 { steps = thumbAccumulator > 0 ? 1 : -1; thumbAccumulator = 0 }
            }
            if p.reverseThumbWheel { steps = -steps }
            for _ in 0..<abs(steps) { thumbStep(thumb, up: steps > 0) }
            return nil
        }
    }

    private func thumbStep(_ a: ThumbWheelAction, up: Bool) {
        switch a {
        case .volume: ActionRunner.mediaKey(up ? 0 : 1)
        case .zoom: ActionRunner.key(up ? 0x18 : 0x1B, .maskCommand)
        case .tabs: ActionRunner.key(0x30, up ? [.maskControl, .maskShift] : .maskControl)
        case .desktops:
            guard Date().timeIntervalSince(lastDesktopSwitch) > 0.4 else { return }
            lastDesktopSwitch = Date()
            ActionRunner.press(Action(up ? .desktopLeft : .desktopRight), mouse: nil)
        case .horizontalScroll, .nothing: break
        }
    }

    private func negate(_ e: CGEvent, axis: Int) {
        let pairs: [(CGEventField, CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2),
        ]
        let (line, fixed, point) = pairs[axis - 1]
        e.setIntegerValueField(line, value: -e.getIntegerValueField(line))
        e.setDoubleValueField(fixed, value: -e.getDoubleValueField(fixed))
        e.setDoubleValueField(point, value: -e.getDoubleValueField(point))
    }
}
