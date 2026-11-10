import SwiftUI
import AppKit
import BetterConnectCore

@main struct BettererConnectApp: App {
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
                .accessibilityLabel("Betterer Connect: \(model.statusTitle)")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        case .ciscoMissing: "Cisco unavailable"
        case .offNetwork: "Waiting for network"
        case .disconnected: "Ready when you are"
        case .connecting: "Connecting"
        case .needsSSO: "Finish signing in"
        case .connected: "You're connected"
        case .reconnecting: "Reconnecting"
        case .error: "Connection needs attention"
        }
    }
    var statusDescription: String {
        switch machine.status {
        case .ciscoMissing: "Install or repair Cisco Secure Client through your IT team."
        case .offNetwork: "No network path. Reconnect will wait until you're online."
        case .disconnected: profileEmpty ? "No VPN profile loaded. Choose or enter your IT-provided gateway." : "Choose a gateway, then connect. Cisco handles your sign-in."
        case .connecting: "Waiting for Cisco to establish the connection."
        case .needsSSO: "Complete sign-in in Cisco. If prompted, select the gateway shown below."
        case .connected: "Cisco reports an active VPN connection."
        case .reconnecting: machine.attempts > 0 ? "Waiting to retry · attempt \(machine.attempts) of 5" : "Cisco is restoring the connection."
        case .error: machine.lastError?.message ?? "Open Cisco for details, then retry."
        }
    }
    var statusColor: Color {
        switch machine.status {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .needsSSO: .blue
        case .ciscoMissing, .error: .red
        case .offNetwork, .disconnected: .secondary
        }
    }
    var symbol: String {
        switch machine.status {
        case .connected: "checkmark.shield.fill"
        case .connecting, .reconnecting: "arrow.triangle.2.circlepath"
        case .needsSSO: "person.crop.circle.badge.exclamationmark"
        case .ciscoMissing, .error: "exclamationmark.shield.fill"
        case .offNetwork: "wifi.slash"
        case .disconnected: "shield"
        }
    }
}
