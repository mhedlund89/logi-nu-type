import AppKit
import ApplicationServices
import Combine
import IOKit.hid
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let state = AppState()
    lazy var engine = Engine(state: state)
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        state.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] in self?.updateStatusButton() }
            .store(in: &cancellables)
        updateStatusButton()

        engine.start()
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        func info(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        func battery(_ d: DeviceSnapshot) -> String {
            guard let b = d.battery else { return "\(d.name)" }
            return "\(d.name) — \(b)%\(d.charging ? " ⚡︎" : "")"
        }

        info(state.mouse.map(battery) ?? "Mouse not connected")
        info(state.keyboard.map(battery) ?? "Keyboard not connected")
        menu.addItem(.separator())

        info("Profile: \(state.config.profile(for: state.frontBundleID)?.name ?? "All apps")")
        if let free = state.freeSpin {
            let item = NSMenuItem(title: "Wheel: \(free ? "Free spin" : "Ratchet") (click to switch)",
                                  action: #selector(toggleWheel), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let smart = NSMenuItem(title: "SmartShift", action: #selector(toggleSmartShift), keyEquivalent: "")
        smart.target = self
        smart.state = state.config.pointer.smartShift ? .on : .off
        menu.addItem(smart)
        menu.addItem(.separator())

        let flow = NSMenuItem(title: "Flow", action: #selector(toggleFlow), keyEquivalent: "")
        flow.target = self
        flow.state = state.config.flow.enabled ? .on : .off
        menu.addItem(flow)
        if state.config.flow.enabled { info("   \(state.flowStatus)") }
        menu.addItem(.separator())

        if !state.accessibilityGranted {
            let item = NSMenuItem(title: "⚠︎ Allow Accessibility access…", action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if !state.inputMonitoringGranted {
            let item = NSMenuItem(title: "⚠︎ Allow Input Monitoring…", action: #selector(openInputMonitoring), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if state.logiOptionsRunning {
            let item = NSMenuItem(title: "⚠︎ Logi Options is running — quit it", action: #selector(quitLogi), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Logi Lite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func toggleWheel() { engine.devices.mouse?.toggleWheelMode() }
    @objc private func toggleSmartShift() { state.config.pointer.smartShift.toggle() }
    @objc private func toggleFlow() {
        if !state.config.flow.enabled && state.config.flow.secret == nil {
            state.config.flow.secret = FlowService.newSecret()
            state.config.flow.enabled = true
            openSettings()
        } else {
            state.config.flow.enabled.toggle()
        }
    }
    @objc private func quitLogi() { Self.quitLogiOptions() }
    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func openInputMonitoring() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
