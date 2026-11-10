import Foundation
import IOKit.hid

/// HID++ 2.0 feature IDs used by Logi Lite.
enum Feature {
    static let root: UInt16 = 0x0000
    static let battery: UInt16 = 0x1000
    static let unifiedBattery: UInt16 = 0x1004
    static let changeHost: UInt16 = 0x1814
    static let reprogControls: UInt16 = 0x1B04
    static let smartShift: UInt16 = 0x2110
    static let adjustableDPI: UInt16 = 0x2201
}

/// One Logitech device spoken to over HID++ 2.0 (long reports, Bluetooth device index 0xFF).
/// All I/O happens on the main run loop; requests are serialised one at a time.
final class HIDPPDevice {
    let device: IOHIDDevice
    let productID: Int
    let name: String

    /// (featureID, function, params) for unsolicited notifications.
    var onNotification: ((UInt16, UInt8, [UInt8]) -> Void)?
    /// Called for every non-HID++ input report (ordinary mouse/keyboard reports). Argument is the report ID.
    var onRawInput: ((UInt8) -> Void)?

    private static let softwareID: UInt8 = 0x0B
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 128)
    private var indexForFeature: [UInt16: UInt8] = [Feature.root: 0]
    private var featureForIndex: [UInt8: UInt16] = [0: Feature.root]

    private struct Request {
        let bytes: [UInt8]
        let completion: ([UInt8]?) -> Void
    }
    private var queue: [Request] = []
    private var inFlight: Request?
    private var timeout: DispatchWorkItem?
    private var isOpen = false

    init(device: IOHIDDevice) {
        self.device = device
        productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
        name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Logitech device"
    }

    deinit {
        close()
        buffer.deallocate()
    }

    func open() -> Bool {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 128, { ctx, _, _, _, _, report, length in
            guard let ctx else { return }
            let me = Unmanaged<HIDPPDevice>.fromOpaque(ctx).takeUnretainedValue()
            me.handleInput(Array(UnsafeBufferPointer(start: report, count: length)))
        }, ctx)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        isOpen = true
        return true
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 128, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        timeout?.cancel()
        let pending = (inFlight.map { [$0] } ?? []) + queue
        inFlight = nil
        queue.removeAll()
        pending.forEach { $0.completion(nil) }
    }

    // MARK: Requests

    /// Resolve a feature ID to its index on this device (nil if unsupported).
    func featureIndex(_ id: UInt16, _ completion: @escaping (UInt8?) -> Void) {
        if let idx = indexForFeature[id] {
            completion(idx == 0 && id != Feature.root ? nil : idx)
            return
        }
        send(index: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 0xFF)]) { [weak self] resp in
            guard let self else { return }
            guard let resp else { completion(nil); return }   // timeout: don't cache
            let idx = resp[0]
            self.indexForFeature[id] = idx
            if idx != 0 { self.featureForIndex[idx] = id }
            completion(idx == 0 ? nil : idx)
        }
    }

    /// Call `function` of `feature` with `params`. Completion receives the response params, or nil on error/timeout/unsupported.
    func call(_ feature: UInt16, _ function: UInt8, _ params: [UInt8] = [],
              _ completion: @escaping ([UInt8]?) -> Void = { _ in }) {
        featureIndex(feature) { [weak self] idx in
            guard let self, let idx else { completion(nil); return }
            self.send(index: idx, function: function, params: params, completion: completion)
        }
    }

    /// Write a request right now without waiting for a reply (used while quitting). Feature must already be resolved.
    func sendImmediately(_ feature: UInt16, _ function: UInt8, _ params: [UInt8]) {
        guard isOpen, let idx = indexForFeature[feature], idx != 0 || feature == Feature.root else { return }
        var bytes: [UInt8] = [0x11, 0xFF, idx, (function << 4) | Self.softwareID] + params
        if bytes.count < 20 { bytes += [UInt8](repeating: 0, count: 20 - bytes.count) }
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), &bytes, 20)
    }

    private func send(index: UInt8, function: UInt8, params: [UInt8], completion: @escaping ([UInt8]?) -> Void) {
        var bytes: [UInt8] = [0x11, 0xFF, index, (function << 4) | Self.softwareID] + params
        if bytes.count < 20 { bytes += [UInt8](repeating: 0, count: 20 - bytes.count) }
        queue.append(Request(bytes: Array(bytes.prefix(20)), completion: completion))
        pump()
    }

    private func pump() {
        guard isOpen, inFlight == nil, !queue.isEmpty else { return }
        let req = queue.removeFirst()
        inFlight = req
        var bytes = req.bytes
        let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(bytes[0]), &bytes, bytes.count)
        if result != kIOReturnSuccess {
            DispatchQueue.main.async { [weak self] in self?.finish(nil) }
            return
        }
        let t = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: t)
    }

    private func finish(_ response: [UInt8]?) {
        timeout?.cancel()
        timeout = nil
        guard let req = inFlight else { return }
        inFlight = nil
        req.completion(response)
        DispatchQueue.main.async { [weak self] in self?.pump() }
    }

    // MARK: Input

    private func handleInput(_ r: [UInt8]) {
        guard let reportID = r.first else { return }
        guard reportID == 0x11 || reportID == 0x10, r.count >= 4 else {
            onRawInput?(reportID)
            return
        }
        // HID++ 2.0 error: [id, dev, 0xFF, featureIndex, fn|sw, code]
        if r[2] == 0xFF || r[2] == 0x8F {
            if let req = inFlight, r.count >= 5, req.bytes[2] == r[3], req.bytes[3] == r[4] { finish(nil) }
            return
        }
        let fnSw = r[3]
        if fnSw & 0x0F == Self.softwareID {
            if let req = inFlight, req.bytes[2] == r[2], req.bytes[3] == fnSw { finish(Array(r[4...])) }
            return
        }
        if fnSw & 0x0F == 0, let feature = featureForIndex[r[2]] {
            onNotification?(feature, fnSw >> 4, Array(r[4...]))
        }
    }
}
