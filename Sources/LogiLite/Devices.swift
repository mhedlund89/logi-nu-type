import Foundation
import IOKit.hid

/// Shared behaviour for a Logitech device: battery and Easy-Switch host.
class LogiDevice {
    let hid: HIDPPDevice
    var name: String { hid.name }
    private(set) var battery: Int?
    private(set) var charging = false
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

    private func parseLegacy(_ r: [UInt8]) {
        guard r.count >= 3 else { return }
        battery = Int(r[0])
        charging = (1...3).contains(r[2])
        onChange?()
    }

    private func parseUnified(_ r: [UInt8]) {
        guard r.count >= 3 else { return }
        battery = Int(r[0])
        charging = r[2] == 1 || r[2] == 2 || r[2] == 3
        onChange?()
    }
}

final class KeyboardController: LogiDevice {}

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
    case native, divert, divertWithMovement
    var flags: UInt8 {
        switch self {
        case .native: return 0x22             // divert=0 (valid), rawXY=0 (valid)
        case .divert: return 0x23             // divert=1 (valid), rawXY=0 (valid)
        case .divertWithMovement: return 0x33 // divert=1 (valid), rawXY=1 (valid)
        }
    }
}

final class MouseController: LogiDevice {
    private(set) var dpi: Int?
    private(set) var freeSpin: Bool?
    private(set) var autoDisengage: Int?

    var onButton: ((UInt16, Bool) -> Void)?
    var onMovement: ((Int, Int) -> Void)?

    private var pressed: Set<UInt16> = []
    private var diversion: [UInt16: DiversionMode] = [:]

    override func start() {
        for f in [Feature.reprogControls, Feature.smartShift, Feature.adjustableDPI] { hid.featureIndex(f) { _ in } }
        super.start()
        refreshWheel()
        refreshDPI()
    }

    // MARK: Buttons

    func setDiversion(_ wanted: [UInt16: DiversionMode]) {
        for cid in ControlID.all {
            let mode = wanted[cid] ?? .native
            guard diversion[cid] != mode else { continue }
            diversion[cid] = mode
            hid.call(Feature.reprogControls, 3, [UInt8(cid >> 8), UInt8(cid & 0xFF), mode.flags])
        }
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
                for cid in now.subtracting(pressed) { onButton?(cid, true) }
                for cid in pressed.subtracting(now) { onButton?(cid, false) }
                pressed = now
            } else if function == 1, params.count >= 4 {
                let dx = Int(Int16(bitPattern: UInt16(params[0]) << 8 | UInt16(params[1])))
                let dy = Int(Int16(bitPattern: UInt16(params[2]) << 8 | UInt16(params[3])))
                onMovement?(dx, dy)
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
