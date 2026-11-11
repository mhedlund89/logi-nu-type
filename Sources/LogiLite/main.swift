import AppKit
import ApplicationServices
import Combine
import IOKit.hid
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    lazy var engine = Engine(state: state)
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var sigterm: DispatchSourceSignal?
    private lazy var panel: MenuPanelController = MenuPanelController { [unowned self] in
        AnyView(MenuPanel(state: self.state, engine: self.engine,
                          openSettings: { [unowned self] in self.panel.close(); self.openSettings() },
                          quitLogiOptions: { Self.quitLogiOptions() },
                          openPrivacy: { Self.openPrivacyPane($0) },
                          onDetach: { [unowned self] in self.panel.pin() },
                          onClose: { [unowned self] in self.panel.close() }))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()
        NSApp.appearance = state.appearance.nsAppearance

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        state.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] in self?.updateStatusButton() }
            .store(in: &cancellables)
        updateStatusButton()

        engine.start()
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { NSApp.terminate(nil) }
        term.resume()
        sigterm = term
        checkEnvironment()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.checkEnvironment() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    // MARK: Permissions & environment

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        state.accessibilityGranted = AXIsProcessTrustedWithOptions(opts)
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        state.inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        Log.info("launch: accessibility=\(state.accessibilityGranted) inputMonitoring=\(state.inputMonitoringGranted) bundle=\(Bundle.main.bundlePath)")
    }

    private func checkEnvironment() {
        let running = NSWorkspace.shared.runningApplications.contains { ($0.bundleIdentifier ?? "").hasPrefix("com.logitech.") }
        if state.logiOptionsRunning != running { state.logiOptionsRunning = running }
        let im = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if state.inputMonitoringGranted != im { state.inputMonitoringGranted = im }
    }

    static func quitLogiOptions() {
        // The daemon is a KeepAlive launch agent, so unload it for this login session, then quit the UI.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/com.logitech.manager.daemon"]
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                NSWorkspace.shared.runningApplications
                    .filter { ($0.bundleIdentifier ?? "").hasPrefix("com.logitech.") }
                    .forEach { $0.terminate() }
            }
        }
        try? p.run()
    }

    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", Bundle.main.bundlePath]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        try? p.run()
    }

    // MARK: Status item

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let img = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: "Logi Lite")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        if let m = state.mouse, m.charging || m.battery != nil {
            let level = m.battery.map { "\($0)%" } ?? ""
            let low = (m.battery ?? 100) <= 15 && !m.charging
            button.title = m.charging ? " ⚡︎\(m.chargeState == .full ? "FULL" : level)" : (low ? " ⚠︎ " : " ") + level
            button.toolTip = "\(m.name): \(m.chargeState.label.capitalized)\(level.isEmpty ? "" : ", \(level)")"
        } else {
            button.title = state.mouse == nil ? " –" : ""
            button.toolTip = state.mouse == nil ? "Mouse not connected" : "Logi Lite"
        }
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button)
    }

    private static func openPrivacyPane(_ anchor: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(state: state, engine: engine))
            host.sizingOptions = [.minSize]   // SwiftUI sets only the minimum; the window stays freely resizable
            let w = NSWindow(contentViewController: host)
            w.title = "Logi Lite"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 1000, height: 700)
            w.setContentSize(NSSize(width: 1240, height: 860))
            w.center()
            w.setFrameAutosaveName("LogiLiteSettings")   // remembers size and position
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// Developer aid: `LogiLite --render-panel out.png [dark]` draws the menu panel with sample data and exits.
// Must run before anything touches the mouse.
if let i = CommandLine.arguments.firstIndex(of: "--render-panel"), CommandLine.arguments.count > i + 1 {
    let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let state = AppState()
    state.mouse = DeviceSnapshot(name: "MX Master 2S", battery: 90, chargeState: .discharging, host: 0, hostCount: 3)
    state.keyboard = DeviceSnapshot(name: "MX Keys Mac", battery: 55, chargeState: .charging, host: 0, hostCount: 3)
    state.freeSpin = false
    state.keyboardMediaKeysFirst = true
    state.frontBundleID = "com.google.Chrome"
    state.accessibilityGranted = true
    state.inputMonitoringGranted = true
    state.logiOptionsRunning = true
    state.flowStatus = "Looking for your other Mac…"
    let scheme: ColorScheme = CommandLine.arguments.contains("dark") ? .dark : .light
    let tabArg = CommandLine.arguments.first { $0.hasPrefix("settings=") }.map { String($0.dropFirst(9)) }
    let view: AnyView
    if let tabArg, let tab = SettingsView.SettingsTab.allCases.first(where: { "\($0)" == tabArg }) {
        view = AnyView(SettingsView(state: state, engine: Engine(state: state), initialTab: tab, scrolls: false)
            .frame(width: 1240, height: CommandLine.arguments.contains("tall") ? 1700 : 1000).environment(\.colorScheme, scheme))
    } else {
        view = AnyView(MenuPanel(state: state, engine: Engine(state: state), openSettings: {}, quitLogiOptions: {}, openPrivacy: { _ in })
            .environment(\.colorScheme, scheme))
    }
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let cg = renderer.cgImage,
           let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? png.write(to: out)
            print("wrote \(out.path)")
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
