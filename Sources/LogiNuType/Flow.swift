import AppKit
import CryptoKit
import Network
import Security

private struct FlowMessage: Codable {
    enum Kind: String, Codable { case hello, enter, clipboard }
    var kind: Kind
    var name: String?
    var mouseHost: Int?
    var keyboardHost: Int?
    var edge: FlowEdge?        // edge of the receiver's screens where the cursor should appear
    var fraction: Double?      // position along that edge, 0…1
    var clipType: String?
    var clipData: Data?
}

/// Flow between two Macs running Logi : nu-type: Bonjour discovery, TLS with a pre-shared key from the pairing code,
/// Easy-Switch of mouse + keyboard when the cursor is pushed past the shared screen edge, and clipboard sync.
final class FlowService {
    static let serviceType = "_logilite._tcp"
    private static let maxClipboardBytes = 20 * 1024 * 1024

    private let state: AppState
    private let devices: DeviceManager
    private let myName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var parameters: NWParameters?
    private var activeSecret: String?
    private var connected = false

    private var push = 0.0
    private var lastSwitch = Date.distantPast
    private var clipTimer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastHello: (Int?, Int?) = (nil, nil)

    init(state: AppState, devices: DeviceManager) {
        self.state = state
        self.devices = devices
    }

    static func newSecret() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let chars = (0..<20).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] }
        return stride(from: 0, to: 20, by: 5).map { String(chars[$0..<$0 + 5]) }.joined(separator: "-")
    }

    // MARK: Lifecycle

    func configure() {
        let f = state.config.flow
        guard f.enabled, let secret = f.secret, !secret.isEmpty else { stop(); state.flowStatus = "Off"; return }
        if secret != activeSecret || listener == nil {
            stop()
            start(secret: secret)
        }
    }

    private func start(secret: String) {
        activeSecret = secret
        let params = Self.parameters(secret: secret)
        parameters = params
        state.flowStatus = "Looking for your other Mac…"

        do {
            let l = try NWListener(using: params)
            l.service = NWListener.Service(name: myName, type: Self.serviceType)
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                if self.connection == nil { self.use(conn) } else { conn.cancel() }
            }
            l.stateUpdateHandler = { [weak self] st in
                if case .failed = st { self?.state.flowStatus = "Network error, retrying…"; self?.restartSoon() }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            state.flowStatus = "Couldn't start: \(error.localizedDescription)"
            return
        }

        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        b.browseResultsChangedHandler = { [weak self] results, _ in self?.connectIfNeeded(results) }
        b.start(queue: .main)
        browser = b

        clipTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in self?.checkClipboard() }
    }

    private func stop() {
        clipTimer?.invalidate(); clipTimer = nil
        connection?.cancel(); connection = nil
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        connected = false
        activeSecret = nil
    }

    private func restartSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.stop()
            self.configure()
        }
    }

    private func connectIfNeeded(_ results: Set<NWBrowser.Result>) {
        guard connection == nil, let params = parameters else { return }
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint, name != myName else { continue }
            // Only one side dials, so the two Macs don't open duplicate connections.
            guard myName < name else { continue }
            use(NWConnection(to: r.endpoint, using: params))
            return
        }
    }

    private func use(_ conn: NWConnection) {
        connection = conn
        conn.stateUpdateHandler = { [weak self, weak conn] st in
            guard let self, let conn, self.connection === conn else { return }
            switch st {
            case .ready:
                self.connected = true
                self.state.flowStatus = "Connected"
                self.lastHello = (nil, nil)
                self.sendHello(force: true)
                self.receive(on: conn)
            case .failed, .cancelled:
                self.dropConnection(conn)
            case .waiting:
                self.dropConnection(conn)
            default: break
            }
        }
        conn.start(queue: .main)
    }

    private func dropConnection(_ conn: NWConnection) {
        guard connection === conn else { return }
        conn.cancel()
        connection = nil
        connected = false
        if state.config.flow.enabled { state.flowStatus = "Looking for your other Mac…" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let results = self.browser?.browseResults else { return }
            self.connectIfNeeded(results)
        }
    }

    // MARK: Messages

    private func send(_ msg: FlowMessage) {
        guard connected, let conn = connection, let body = try? JSONEncoder().encode(msg) else { return }
        var len = UInt32(body.count).bigEndian
        var frame = Data(bytes: &len, count: 4)
        frame.append(body)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, data.count == 4 else { self?.dropConnection(conn); return }
            let len = data.reduce(0) { Int($0) << 8 | Int($1) }
            guard len > 0, len <= Self.maxClipboardBytes * 2 else { self.dropConnection(conn); return }
            conn.receive(minimumIncompleteLength: len, maximumLength: len) { [weak self] body, _, _, error in
                guard let self, error == nil, let body,
                      let msg = try? JSONDecoder().decode(FlowMessage.self, from: body) else { self?.dropConnection(conn); return }
                self.handle(msg)
                self.receive(on: conn)
            }
        }
    }

    private func handle(_ msg: FlowMessage) {
        switch msg.kind {
        case .hello:
            var f = state.config.flow
            f.peerName = msg.name ?? f.peerName
            if let h = msg.mouseHost { f.peerMouseHost = h }
            if let h = msg.keyboardHost { f.peerKeyboardHost = h }
            if f != state.config.flow { state.config.flow = f }
            state.flowStatus = "Connected to \(f.peerName ?? "other Mac")"
        case .enter:
            guard let edge = msg.edge else { return }
            let b = Self.screenBounds()
            let t = min(max(msg.fraction ?? 0.5, 0), 1)
            let p: CGPoint
            switch edge {
            case .left: p = CGPoint(x: b.minX + 4, y: b.minY + t * b.height)
            case .right: p = CGPoint(x: b.maxX - 5, y: b.minY + t * b.height)
            case .top: p = CGPoint(x: b.minX + t * b.width, y: b.minY + 4)
            case .bottom: p = CGPoint(x: b.minX + t * b.width, y: b.maxY - 5)
            }
            CGWarpMouseCursorPosition(p)
            CGAssociateMouseAndMouseCursorPosition(1)
            lastSwitch = Date()
        case .clipboard:
            guard state.config.flow.clipboard, let data = msg.clipData else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            switch msg.clipType {
            case "text": pb.setString(String(decoding: data, as: UTF8.self), forType: .string)
            case "png": pb.setData(data, forType: .png)
            case "tiff": pb.setData(data, forType: .tiff)
            default: break
            }
            lastChangeCount = pb.changeCount
        }
    }

    /// Tell the other Mac which Easy-Switch slot this Mac occupies on each device.
    func devicesChanged() { sendHello(force: false) }

    private func sendHello(force: Bool) {
        let hosts = (devices.mouse?.hostIndex, devices.keyboard?.hostIndex)
        guard force || hosts != lastHello else { return }
        lastHello = hosts
        send(FlowMessage(kind: .hello, name: myName, mouseHost: hosts.0, keyboardHost: hosts.1))
    }

    // MARK: Edge switching

    func pointerMoved(_ e: CGEvent, isDrag: Bool) {
        let f = state.config.flow
        guard f.enabled, connected, !isDrag, let peerMouse = f.peerMouseHost,
              let mouse = devices.mouse, mouse.hostIndex != peerMouse,
              Date().timeIntervalSince(lastSwitch) > 2,
              Date().timeIntervalSince(devices.lastMouseActivity) < 0.3 else { push = 0; return }
        if f.requireControl && !e.flags.contains(.maskControl) { push = 0; return }

        let loc = e.location
        let dx = e.getDoubleValueField(.mouseEventDeltaX)
        let dy = e.getDoubleValueField(.mouseEventDeltaY)
        let b = Self.screenBounds()
        let outward: Double
        let fraction: Double
        switch f.otherMacEdge {
        case .left: outward = loc.x <= b.minX + 1 ? -dx : 0; fraction = (loc.y - b.minY) / b.height
        case .right: outward = loc.x >= b.maxX - 2 ? dx : 0; fraction = (loc.y - b.minY) / b.height
        case .top: outward = loc.y <= b.minY + 1 ? -dy : 0; fraction = (loc.x - b.minX) / b.width
        case .bottom: outward = loc.y >= b.maxY - 2 ? dy : 0; fraction = (loc.x - b.minX) / b.width
        }
        push = outward > 0 ? push + outward : 0
        guard push > 60 else { return }

        push = 0
        lastSwitch = Date()
        send(FlowMessage(kind: .enter, edge: f.otherMacEdge.opposite, fraction: fraction))
        let keyboardHost = f.keyboardFollows ? f.peerKeyboardHost : nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.devices.mouse?.switchHost(to: peerMouse)
            if let k = keyboardHost, self?.devices.keyboard?.hostIndex != k { self?.devices.keyboard?.switchHost(to: k) }
        }
    }

    private static func screenBounds() -> CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map { CGDisplayBounds($0) }.reduce(CGRect.null) { $0.union($1) }
    }

    // MARK: Clipboard

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard connected, state.config.flow.clipboard else { return }
        if let s = pb.string(forType: .string) {
            send(FlowMessage(kind: .clipboard, clipType: "text", clipData: Data(s.utf8)))
        } else if let png = pb.data(forType: .png), png.count <= Self.maxClipboardBytes {
            send(FlowMessage(kind: .clipboard, clipType: "png", clipData: png))
        } else if let tiff = pb.data(forType: .tiff), tiff.count <= Self.maxClipboardBytes {
            send(FlowMessage(kind: .clipboard, clipType: "tiff", clipData: tiff))
        }
    }

    // MARK: TLS-PSK

    private static func parameters(secret: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let normalized = secret.uppercased().filter { $0.isLetter || $0.isNumber }
        let key = Data(SHA256.hash(data: Data(("logilite-flow-v1:" + normalized).utf8)))
        let keyData = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("logilite".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, keyData as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
                                                    tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.noDelay = true
        return NWParameters(tls: tls, tcp: tcp)
    }
}
