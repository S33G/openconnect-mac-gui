import SwiftUI
import AppKit
import OpenConnectCore

@main struct OpenConnectMacGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(model.statusColor, .primary)
                .help(model.statusDescription)
                .accessibilityLabel("OpenConnect Mac GUI: \(model.statusTitle)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--render-previews"), arguments.indices.contains(index + 1) {
            Task {
                do { try await PreviewRenderer.render(to: URL(fileURLWithPath: arguments[index + 1])) }
                catch { fputs("Could not render documentation previews.\n", stderr) }
                NSApplication.shared.terminate(nil)
            }
            return
        }
        if !UserDefaults.standard.bool(forKey: "HasLaunched") || ProcessInfo.processInfo.arguments.contains("--show-window") {
            AppModel.shared.showWindow()
            UserDefaults.standard.set(true, forKey: "HasLaunched")
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showWindow()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.stop() }
}

extension AppModel {
    var statusTitle: String {
        switch machine.status {
        case .dependenciesMissing: "OpenConnect setup needed"
        case .offNetwork: "Waiting for network"
        case .disconnected: "Ready when you are"
        case .permission: "Allow the VPN connection"
        case .connecting: "Connecting"
        case .needsSSO: "Finish signing in"
        case .connected: "You're connected"
        case .reconnecting: "Reconnecting"
        case .disconnecting: "Disconnecting"
        case .error: "Connection needs attention"
        }
    }
    var statusDescription: String {
        switch machine.status {
        case .dependenciesMissing: "Install OpenConnect and Python 3.11 or newer, then re-check."
        case .offNetwork: "No network path. Reconnect will wait until you're online."
        case .disconnected: "Choose a gateway and authentication group, then connect."
        case .permission: "Complete the Mac administrator prompt in Terminal."
        case .connecting: "OpenConnect is establishing the VPN tunnel."
        case .needsSSO: "Complete sign-in in your default browser."
        case .connected: "OpenConnect configured an active VPN tunnel."
        case .reconnecting: machine.attempts > 0 ? "Waiting to retry · attempt \(machine.attempts) of 5" : "OpenConnect is restoring the connection."
        case .disconnecting: "Waiting for OpenConnect to remove the tunnel and restore networking."
        case .error: machine.lastError?.message ?? SafeError.commandFailed.message
        }
    }
    var statusColor: Color {
        switch machine.status {
        case .connected: .green
        case .connecting, .reconnecting, .disconnecting: .orange
        case .needsSSO, .permission: .accentColor
        case .dependenciesMissing, .error: .red
        case .offNetwork, .disconnected: .secondary
        }
    }
    var symbol: String {
        switch machine.status {
        case .connected: "checkmark.shield.fill"
        case .connecting, .reconnecting, .disconnecting: "arrow.triangle.2.circlepath"
        case .needsSSO, .permission: "person.crop.circle.badge.exclamationmark"
        case .dependenciesMissing, .error: "exclamationmark.shield.fill"
        case .offNetwork: "wifi.slash"
        case .disconnected: "shield"
        }
    }
}
