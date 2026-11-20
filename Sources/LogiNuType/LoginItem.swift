import Foundation
import ServiceManagement

/// "Open at login". macOS 13+ uses SMAppService; macOS 12 has no SMAppService for the main app,
/// so there it writes a per-user LaunchAgent that opens the app bundle at login.
enum LoginItem {
    private static let label = "local.loginutype.login"
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ on: Bool) throws {
        if #available(macOS 13.0, *) {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return
        }
        if on {
            let plist: [String: Any] = [
                "Label": label,
                // `open` rather than the binary itself, so the app launches as a normal app
                // and keeps its own Accessibility / Input Monitoring permissions.
                "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: agentURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: agentURL.path) {
            try FileManager.default.removeItem(at: agentURL)
        }
    }
}
