import AppKit
import OpenConnectCore
import Network
import SwiftUI
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel(demo: (ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.arguments.contains("--render-previews")))
    @Published private(set) var machine: ConnectionMachine
    @Published private(set) var installation = OpenConnectInstallation()
    @Published private(set) var gateways: [String] = []
    @Published private(set) var note = ""
    @Published private(set) var config: Configuration
    @Published private(set) var sessionServer: String?
    @Published private(set) var sessionGroup: String?
    @Published private(set) var previousBuildRunning = false
    @Published var groupInput: String
    private let monitor = NWPathMonitor()
    private var loop: Task<Void, Never>?
    private var session: OpenConnectSession?
    private var sessionStarted = Date()
    private var reconnectAfterStop = false
    private let demo: Bool
    private var window: NSWindow?
    var busy: Bool { [.permission, .connecting, .reconnecting, .disconnecting].contains(machine.status) }
    var canConnect: Bool { !previousBuildRunning && machine.available && machine.online && !machine.sessionActive && [.disconnected, .error].contains(machine.status) }
    var canDisconnect: Bool { machine.sessionActive || machine.wantsConnection }
    var autoReconnectManaged: Bool { UserDefaults.standard.objectIsForced(forKey: "AutoReconnect") }
    var backgroundManaged: Bool { UserDefaults.standard.objectIsForced(forKey: "RunInBackground") }
    var groupManaged: Bool { UserDefaults.standard.objectIsForced(forKey: "PreferredGroup") }

    init(demo: Bool = false) {
        self.demo = demo
        let config = ConfigStore.read()
        self.config = config; self.groupInput = config.preferredGroup
        self.machine = ConnectionMachine(configuration: config); self.gateways = config.gateways
        if demo {
            self.config = Configuration(gateways: ["vpn.example.com"])
            machine = ConnectionMachine(configuration: self.config)
            machine.setAvailable(true); gateways = ["vpn.example.com"]
            groupInput = ""
            note = "Preview mode · no VPN commands are run"
            return
        }
        installation = .detect(); machine.setAvailable(installation.present)
        previousBuildRunning = Self.previousBuildIsRunning()
        recoverPreviousSession()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.machine.setNetwork(online)
                if !online && !self.config.autoReconnect { self.disconnect() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "openconnect-mac-gui.network"))
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    private static func previousBuildIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "io.github.bettererconnect" }
    }
    private func recoverPreviousSession() {
        guard !demo else { return }
        if previousBuildRunning {
            note = "Quit the previous development build before connecting here."
            return
        }
        guard session == nil, let existing = OpenConnectSession.recover() else { return }
        session = existing; machine.adoptRecoveredSession(gateway: existing.request.host)
        sessionServer = existing.request.host; sessionGroup = existing.request.group
        existing.stop(); machine.requestStop()
        note = "Cleaning up the previous session before starting another."
    }
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "OpenConnect Mac GUI"
            window.contentView = NSHostingView(rootView: MenuContent(model: self))
            window.isReleasedWhenClosed = false; window.center(); self.window = window
        }
        window?.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func stop() { session?.stop(); loop?.cancel(); monitor.cancel() }
    func choose(_ host: String) {
        guard !machine.sessionActive, let host = Gateway.normalize(host) else { return }
        UserDefaults.standard.set(host, forKey: "LastSelectedGateway"); machine.selectedGateway = host
    }
    func addGateway(_ input: String) {
        guard !machine.sessionActive, let host = Gateway.normalize(input) else { return }
        if !gateways.contains(host) { gateways.append(host) }
        if !UserDefaults.standard.objectIsForced(forKey: "GatewayList") { UserDefaults.standard.set(gateways, forKey: "GatewayList") }
        choose(host); note = "Gateway selection saved."
    }
    func connect() { startConnection(retry: false) }
    private func startConnection(retry: Bool) {
        guard !demo, !Self.previousBuildIsRunning(), session == nil else { return }
        let group = groupInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard group.count <= 80, !group.hasPrefix("-"), !group.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            note = "Enter an authentication group of at most 80 characters, without control characters or a leading dash."; return
        }
        guard machine.begin(now: now, retry: retry), let host = machine.selectedGateway else { return }
        if !groupManaged { UserDefaults.standard.set(group, forKey: "PreferredGroup") }
        do {
            let created = try OpenConnectSession.create(installation: installation, host: host, group: group, automatic: config.autoReconnect, background: config.runInBackground)
            session = created; sessionStarted = Date(); sessionServer = host; sessionGroup = group.isEmpty ? nil : group
            note = "Complete the administrator prompt in Terminal, then sign in through your default browser."
            Task {
                do { try await created.launch() }
                catch {
                    // Stop marker also protects against a delayed Terminal launch.
                    created.stop()
                    guard self.session === created else { return }
                    machine.requestStop()
                    note = "Terminal could not open. Check macOS permissions, then retry."
                }
            }
        } catch { machine.launchFailed() }
    }
    func disconnect() { reconnectAfterStop = false; machine.requestStop(); session?.stop(); note = session == nil ? "VPN session stopped." : "Waiting for tunnel teardown." }
    func cancelSignIn() { disconnect() }
    func reconnectNow() {
        guard session != nil else { connect(); return }
        disconnect(); reconnectAfterStop = true
    }
    func setAutoReconnect(_ enabled: Bool) {
        guard !autoReconnectManaged, !machine.sessionActive else { return }
        UserDefaults.standard.set(enabled, forKey: "AutoReconnect")
        config = ConfigStore.read(); machine.configuration = config
    }
    func setRunInBackground(_ enabled: Bool) {
        guard !backgroundManaged, !machine.sessionActive else { return }
        UserDefaults.standard.set(enabled, forKey: "RunInBackground")
        config = ConfigStore.read(); machine.configuration = config
    }
    func recheck() { installation = .detect(); machine.setAvailable(installation.present); refresh() }
    func openTerminal() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")) }
    func copyInstallCommand() {
        copy("brew install openconnect python@3.11")
        note = "Install command copied. Run it in Terminal, then re-check."
        openTerminal()
    }
    func enableNotifications() {
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                note = allowed ? "Notifications enabled." : "Enable notifications in System Settings."
            } catch { note = "Could not request notifications. Check System Settings." }
        }
    }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func copyDiagnostics() {
        copy("""
        OpenConnect Mac GUI \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        OpenConnect installed: \(installation.openconnect != nil)
        Python runtime found: \(installation.python != nil)
        State: \(machine.status.rawValue)
        Session owned: \(machine.sessionActive)
        Auto reconnect: \(config.autoReconnect)
        Background mode: \(config.runInBackground)
        Last error: \(machine.lastError?.rawValue ?? "none")
        """)
        note = config.supportChannel.isEmpty ? "Diagnostics copied. No gateway, username, or authentication output included." : "Diagnostics copied. Send to \(config.supportChannel)."
    }
    private func refresh() {
        guard !demo else { return }
        let wasBlocked = previousBuildRunning
        previousBuildRunning = Self.previousBuildIsRunning()
        if wasBlocked && !previousBuildRunning { note = "" }
        recoverPreviousSession()
        let previous = machine.status
        if let session {
            session.heartbeat()
            if let value = session.read() {
                if Date().timeIntervalSince1970 - value.updatedAt > 8 { machine.stale() }
                else { machine.observe(phase: value.phase, finished: value.finished, now: now) }
                if value.finished {
                    // Finished is emitted only after the complete process group exits.
                    machine.observe(phase: value.phase, finished: true, now: now)
                    session.cleanup(); self.session = nil
                    note = machine.status == .disconnected ? "VPN session stopped." : ""
                    if reconnectAfterStop { reconnectAfterStop = false; connect() }
                }
            } else if Date().timeIntervalSince(sessionStarted) > 30 { machine.stale() }
        } else if let retry = machine.retryAt, now >= retry, machine.online { startConnection(retry: true) }
        if previous != machine.status && machine.status == .connected {
            UserDefaults.standard.set(sessionServer, forKey: "LastUsedGateway")
            note = config.runInBackground ? "VPN is running in the background. You can close Terminal; keep this app running." : "VPN connected. Keep the Terminal window open until disconnected."
            notifyConnected()
        }
    }
    private func notifyConnected() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent(); content.title = "OpenConnect Mac GUI"; content.body = "OpenConnect configured the VPN tunnel."
            try? await center.add(UNNotificationRequest(identifier: "connection-status", content: content, trigger: nil))
        }
    }
}
