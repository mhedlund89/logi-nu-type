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
    private lazy var panel: MenuPanelController = MenuPanelController { [unowned self] in
        AnyView(MenuPanel(state: self.state, engine: self.engine,
                          openSettings: { [unowned self] in self.panel.close(); self.openSettings() },
                          quitLogiOptions: { Self.quitLogiOptions() },
                          openPrivacy: { Self.openPrivacyPane($0) }))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()

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
        if UserDefaults.standard.bool(forKey: "debugActions") {
            // Debug only: `defaults write local.logilite.app debugActions -bool true`, then post
            // a distributed notification named local.logilite.debug.<actionKind> to run an action in-process.
            for kind in ActionKind.allCases {
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name("local.logilite.debug.\(kind.rawValue)"), object: nil, queue: .main) { [weak self] _ in
                    Log.info("debug trigger: \(kind.rawValue) axTrusted=\(AXIsProcessTrusted())")
                    ActionRunner.press(Action(kind), mouse: self?.engine.devices.mouse)
                    ActionRunner.release(Action(kind))
                }
            }
        }
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
        try? p.run()
        p.waitUntilExit()
        NSWorkspace.shared.runningApplications
            .filter { ($0.bundleIdentifier ?? "").hasPrefix("com.logitech.") }
            .forEach { $0.terminate() }
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
        if let m = state.mouse, let level = m.battery {
            let low = level <= 15 && !m.charging
            button.title = (low ? " ⚠︎ " : " ") + "\(level)%"
            button.toolTip = "\(m.name): \(level)%\(m.charging ? " (charging)" : "")"
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
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state, engine: engine)))
            w.title = "Logi Lite"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 760, height: 640))
            w.center()
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
    state.mouse = DeviceSnapshot(name: "MX Master 2S", battery: 90, charging: false, host: 0, hostCount: 3)
    state.keyboard = DeviceSnapshot(name: "MX Keys Mac", battery: 55, charging: true, host: 0, hostCount: 3)
    state.freeSpin = false
    state.frontBundleID = "com.google.Chrome"
    state.accessibilityGranted = true
    state.inputMonitoringGranted = true
    state.logiOptionsRunning = true
    state.flowStatus = "Looking for your other Mac…"
    let view = MenuPanel(state: state, engine: Engine(state: state), openSettings: {}, quitLogiOptions: {}, openPrivacy: { _ in })
        .environment(\.colorScheme, CommandLine.arguments.contains("dark") ? .dark : .light)
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
