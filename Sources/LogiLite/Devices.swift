import Foundation
import IOKit.hid

/// What the device says about its power source.
enum ChargeState: String, Equatable {
    case discharging, charging, slowCharging, full, error

    var onPower: Bool { self != .discharging }
    var label: String {
        switch self {
        case .discharging: return "ON BATTERY"
        case .charging: return "CHARGING"
        case .slowCharging: return "SLOW CHARGE"
        case .full: return "FULL"
        case .error: return "CHARGE ERROR"
        }
    }
}

/// Shared behaviour for a Logitech device: battery and Easy-Switch host.
class LogiDevice {
    let hid: HIDPPDevice
    var name: String { hid.name }
    private(set) var battery: Int?
    private(set) var chargeState = ChargeState.discharging
    private(set) var hostIndex: Int?
    private(set) var hostCount: Int?
    var onChange: (() -> Void)?

    init(hid: HIDPPDevice) {
        self.hid = hid
        hid.onNotification = { [weak self] feature, function, params in
            self?.handleNotification(feature: feature, function: function, params: params)
        }
    }

    func start() {
        // Resolve features up front so notifications can be mapped back to them.
        for f in [Feature.battery, Feature.unifiedBattery, Feature.changeHost] { hid.featureIndex(f) { _ in } }
        refreshBattery()
        refreshHost()
    }

    func refreshBattery() {
        hid.call(Feature.unifiedBattery, 1) { [weak self] r in
            guard let self else { return }
            if let r { self.parseUnified(r); return }
            self.hid.call(Feature.battery, 0) { [weak self] r in
                if let r { self?.parseLegacy(r) }
            }
        }
    }

    func refreshHost() {
        hid.call(Feature.changeHost, 0) { [weak self] r in
            guard let self, let r, r.count >= 2 else { return }
            self.hostCount = Int(r[0])
            self.hostIndex = Int(r[1])
            self.onChange?()
        }
    }

    /// Easy-Switch to another host slot (0-based). The device disconnects from this Mac immediately.
    func switchHost(to index: Int) {
        hid.call(Feature.changeHost, 1, [UInt8(index)])
    }

    func handleNotification(feature: UInt16, function: UInt8, params: [UInt8]) {
        switch feature {
        case Feature.battery where function == 0: parseLegacy(params)
        case Feature.unifiedBattery where function == 0: parseUnified(params)
        default: break
        }
    }

    /// Feature 0x1000: [level %, next level %, status]. While on power the level is reported as 0 ("not
    /// measured"), so keep the last real reading instead of showing 0%.
    private func parseLegacy(_ r: [UInt8]) {
        guard r.count >= 3 else { return }
        switch r[2] {
        case 0: chargeState = .discharging
        case 1, 2: chargeState = .charging          // recharging / final stage
        case 3: chargeState = .full
        case 4: chargeState = .slowCharging
        default: chargeState = .error               // invalid battery, thermal, other
        }
        let level = Int(r[0])
        if level > 0 || chargeState == .discharging { battery = level }
        else if chargeState == .full { battery = 100 }
        onChange?()
    }

    /// Feature 0x1004: [state of charge %, level flags, charging status, external power].
    private func parseUnified(_ r: [UInt8]) {
        guard r.count >= 3 else { return }
        switch r[2] {
        case 0: chargeState = .discharging
        case 1: chargeState = .charging
        case 2: chargeState = .slowCharging
        case 3: chargeState = .full
        default: chargeState = .error
        }
        if r[0] > 0 || chargeState == .discharging { battery = Int(r[0]) }
        onChange?()
    }
}

final class KeyboardController: LogiDevice {
    /// true = the top row sends media/special keys and fn gives F1–F12 (the MX Keys default);
    /// false = standard F1–F12 and fn gives the media keys. nil until read, or if the keyboard has no such setting.
    private(set) var mediaKeysFirst: Bool?
    private var fnFeature: UInt16?

    override func start() {
        for f in Feature.fnInversions + [Feature.reprogControls] { hid.featureIndex(f) { _ in } }
        super.start()
        refreshFnMode()
        logControls()
    }

    /// Find the first fn-inversion feature the keyboard supports, then read it.
    func refreshFnMode(_ candidates: [UInt16] = Feature.fnInversions) {
        if let f = fnFeature { readFnMode(f); return }
        guard let f = candidates.first else { Log.info("keyboard: no F-key mode feature"); return }
        hid.featureIndex(f) { [weak self] idx in
            guard let self else { return }
            if idx == nil { self.refreshFnMode(Array(candidates.dropFirst())); return }
            self.fnFeature = f
            self.readFnMode(f)
        }
    }

    private func readFnMode(_ f: UInt16) {
        // 0x40A3 is per host: pass 0xFF ("this host") and skip the host byte in the reply.
        let multi = f == Feature.fnInversionMultiHost
        hid.call(f, 0, multi ? [0xFF] : []) { [weak self] r in
            guard let self, let r else { return }
            let i = multi ? 1 : 0
            guard r.count > i else { return }
            self.mediaKeysFirst = r[i] & 1 == 1
            Log.info(String(format: "keyboard: F-key mode feature 0x%04X reply %@ -> mediaKeysFirst=%@", f,
                            r.prefix(4).map { String(format: "%02X", $0) }.joined(separator: " "), "\(self.mediaKeysFirst!)"))
            self.onChange?()
        }
    }

    func setMediaKeysFirst(_ on: Bool) {
        guard let f = fnFeature else { return }
        let multi = f == Feature.fnInversionMultiHost
        hid.call(f, 1, (multi ? [0xFF] : []) + [on ? 1 : 0]) { [weak self] _ in self?.readFnMode(f) }
    }

    override func handleNotification(feature: UInt16, function: UInt8, params: [UInt8]) {
        // fn + Esc on the keyboard flips the mode and announces it.
        if Feature.fnInversions.contains(feature) { if let f = fnFeature { readFnMode(f) }; return }
        super.handleNotification(feature: feature, function: function, params: params)
    }

    /// Log the keyboard's programmable keys once (control ID, task, flags) — groundwork for per-key remapping.
    private func logControls() {
        hid.call(Feature.reprogControls, 0) { [weak self] r in
            guard let self, let count = r?.first, count > 0 else { return }
            var rows: [String] = []
            for i in 0..<count {
                self.hid.call(Feature.reprogControls, 1, [i]) { r in
                    if let r, r.count >= 5 {
                        rows.append(String(format: "cid=0x%04X task=0x%04X flags=0x%02X", Int(r[0]) << 8 | Int(r[1]),
                                           Int(r[2]) << 8 | Int(r[3]), r[4]))
                    }
                    if i == count - 1 { Log.info("keyboard controls (\(rows.count)): " + rows.joined(separator: "; ")) }
                }
            }
        }
    }
}

/// Divertable controls on the MX Master 2S.
enum ControlID {
    static let middle: UInt16 = 0x52
    static let back: UInt16 = 0x53
    static let forward: UInt16 = 0x56
    static let gesture: UInt16 = 0xC3
    static let wheelMode: UInt16 = 0xC4
    static let all: [UInt16] = [middle, back, forward, gesture, wheelMode]
}

enum DiversionMode: Equatable {
    case native, divert
    /// setCidReporting flags. Raw-XY is always written as "off (valid)" so a previous run can't leave it on.
    var flags: UInt8 {
        switch self {
        case .native: return 0x22 // divert=0 (valid), rawXY=0 (valid)
        case .divert: return 0x23 // divert=1 (valid), rawXY=0 (valid)
        }
    }
}

final class MouseController: LogiDevice {
    private(set) var dpi: Int?
    private(set) var freeSpin: Bool?
    private(set) var autoDisengage: Int?

    var onButton: ((UInt16, Bool) -> Void)?

    private var pressed: Set<UInt16> = []
    private var diversion: [UInt16: DiversionMode] = [:]

    override func start() {
        for f in [Feature.reprogControls, Feature.smartShift, Feature.adjustableDPI] { hid.featureIndex(f) { _ in } }
        super.start()
        refreshWheel()
        refreshDPI()
    }

    // MARK: Buttons

    /// Diversion requested while a button was held; applied once everything is released.
    private var pendingDiversion: [UInt16: DiversionMode]?

    var isAnyButtonHeld: Bool { !pressed.isEmpty }

    /// Changing a control's reporting while a diverted button is held makes the MX Master 2S lose that
    /// button's release event (it then stays "held" and streams movement to us). So never write mid-press.
    func setDiversion(_ wanted: [UInt16: DiversionMode]) {
        if isAnyButtonHeld { pendingDiversion = wanted; return }
        pendingDiversion = nil
        for cid in ControlID.all {
            let mode = wanted[cid] ?? .native
            guard diversion[cid] != mode else { continue }
            diversion[cid] = mode
            hid.call(Feature.reprogControls, 3, [UInt8(cid >> 8), UInt8(cid & 0xFF), mode.flags])
        }
    }

    /// Recover a control the mouse believes is stuck down: cycle its reporting off and back on.
    func resetStuckControl(_ cid: UInt16) {
        let mode = diversion[cid] ?? .native
        pressed.remove(cid)
        hid.call(Feature.reprogControls, 3, [UInt8(cid >> 8), UInt8(cid & 0xFF), DiversionMode.native.flags])
        if mode != .native {
            hid.call(Feature.reprogControls, 3, [UInt8(cid >> 8), UInt8(cid & 0xFF), mode.flags])
        }
        if pressed.isEmpty, let pending = pendingDiversion { setDiversion(pending) }
    }

    /// Hand every button back to the mouse's built-in behaviour, synchronously (safe to call while quitting).
    func restoreNativeButtons() {
        for (cid, mode) in diversion where mode != .native {
            hid.sendImmediately(Feature.reprogControls, 3, [UInt8(cid >> 8), UInt8(cid & 0xFF), DiversionMode.native.flags])
        }
        diversion.removeAll()
    }

    override func handleNotification(feature: UInt16, function: UInt8, params: [UInt8]) {
        if feature == Feature.reprogControls {
            if function == 0 {
                var now: Set<UInt16> = []
                for i in stride(from: 0, to: min(params.count, 8), by: 2) {
                    let cid = UInt16(params[i]) << 8 | UInt16(params[i + 1])
                    if cid != 0 { now.insert(cid) }
                }
                let downs = now.subtracting(pressed), ups = pressed.subtracting(now)
                pressed = now
                for cid in downs { onButton?(cid, true) }
                for cid in ups { onButton?(cid, false) }
                if now.isEmpty, let pending = pendingDiversion { setDiversion(pending) }
            }
            return
        }
        if feature == Feature.smartShift { refreshWheel(); return }
        super.handleNotification(feature: feature, function: function, params: params)
    }

    // MARK: Wheel

    func refreshWheel() {
        hid.call(Feature.smartShift, 0) { [weak self] r in
            guard let self, let r, r.count >= 2 else { return }
            self.freeSpin = r[0] == 1
            self.autoDisengage = Int(r[1])
            self.onChange?()
        }
    }

    func toggleWheelMode() {
        let next: UInt8 = (freeSpin ?? false) ? 2 : 1
        hid.call(Feature.smartShift, 1, [next, 0, 0]) { [weak self] _ in self?.refreshWheel() }
    }

    /// SmartShift on = wheel switches to free spin when flicked faster than `threshold` (1–50).
    func setSmartShift(enabled: Bool, threshold: Int) {
        let value = enabled ? UInt8(max(1, min(threshold, 254))) : 0xFF
        // wheelMode 0 = leave ratchet/free-spin as it is; only change the auto-disengage threshold.
        hid.call(Feature.smartShift, 1, [0, value, 0]) { [weak self] _ in self?.refreshWheel() }
    }

    // MARK: DPI

    func refreshDPI() {
        hid.call(Feature.adjustableDPI, 2, [0]) { [weak self] r in
            guard let self, let r, r.count >= 3 else { return }
            self.dpi = Int(r[1]) << 8 | Int(r[2])
            self.onChange?()
        }
    }

    func setDPI(_ value: Int) {
        let v = UInt16(max(200, min(value, 4000)))
        hid.call(Feature.adjustableDPI, 3, [0, UInt8(v >> 8), UInt8(v & 0xFF)]) { [weak self] _ in self?.refreshDPI() }
    }
}

/// Watches for the mouse and keyboard to appear and disappear (Bluetooth devices reconnect after sleep).
final class DeviceManager {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private(set) var mouse: MouseController?
    private(set) var keyboard: KeyboardController?
    /// Last time the MX mouse sent an ordinary movement/scroll report.
    private(set) var lastMouseActivity = Date.distantPast

    var onMouseAttached: ((MouseController) -> Void)?
    var onKeyboardAttached: ((KeyboardController) -> Void)?
    var onChange: (() -> Void)?

    func start() {
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<DeviceManager>.fromOpaque(ctx).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<DeviceManager>.fromOpaque(ctx).takeUnretainedValue().detach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        let maxOut = (IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString) as? Int) ?? 0
        guard maxOut >= 20 else { return } // no HID++ long reports on this interface
        let hid = HIDPPDevice(device: device)
        let lower = hid.name.lowercased()
        let isKeyboard = lower.contains("keys") || lower.contains("craft") || lower.contains("keyboard")
        let isMouse = !isKeyboard && (lower.contains("master") || lower.contains("anywhere") || lower.contains("mouse") || hid.productID == 0xB019)
        guard isKeyboard || isMouse, hid.open() else { return }

        if isMouse {
            mouse?.hid.close()
            let m = MouseController(hid: hid)
            hid.onRawInput = { [weak self] _ in self?.lastMouseActivity = Date() }
            m.onChange = { [weak self] in self?.onChange?() }
            mouse = m
            m.start()
            onMouseAttached?(m)
        } else {
            keyboard?.hid.close()
            let k = KeyboardController(hid: hid)
            k.onChange = { [weak self] in self?.onChange?() }
            keyboard = k
            k.start()
            onKeyboardAttached?(k)
        }
        onChange?()
    }

    private func detach(_ device: IOHIDDevice) {
        if let m = mouse, m.hid.device == device { m.hid.close(); mouse = nil }
        if let k = keyboard, k.hid.device == device { k.hid.close(); keyboard = nil }
        onChange?()
    }
}
