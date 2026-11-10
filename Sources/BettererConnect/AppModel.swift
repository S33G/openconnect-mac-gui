import AppKit
import BetterConnectCore
import Network
import OSLog
import SwiftUI
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    @Published private(set) var machine: ConnectionMachine
    @Published private(set) var installation = CiscoInstallation()
    @Published private(set) var gateways: [String] = []
    @Published private(set) var busy = false
    @Published private(set) var profileEmpty = false
    @Published private(set) var note = ""
    @Published private(set) var config: Configuration
    @Published private(set) var sessionServer: String?
    @Published private(set) var sessionGroup: String?
    private let runner = ProcessRunner()
    private let monitor = NWPathMonitor()
    private let logger = Logger(subsystem: "io.github.bettererconnect", category: "state")
    private var loop: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var lastDiscovery: Double = -.infinity
    private var lastStats: Double = -.infinity
    private var pollInProgress = false
    private var sleeping = false
    private var pathSignature: String?
    private var reconnectIntent = ReconnectIntent()
    private let demo: Bool
    private var window: NSWindow?

    init(demo: Bool = false) {
        self.demo = demo
        let config = ConfigStore.read()
        self.config = config
        self.machine = ConnectionMachine(configuration: config)
        self.gateways = config.gateways
        if demo {
            machine = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"]))
            _ = machine.handle(.availability(true), now: now)
            gateways = ["vpn.example.com"]
            note = "Preview mode · no Cisco commands are run"
            return
        }
        startWatchers()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                self.send(.tick)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 590),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Betterer Connect"
            window.contentView = NSHostingView(rootView: MenuContent(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func stop() {
        loop?.cancel(); operation?.cancel(); runner.cancel(); monitor.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    var canConnect: Bool { machine.available && machine.online && !busy && !sleeping && [.disconnected, .error].contains(machine.status) }
    var canDisconnect: Bool { machine.available && !sleeping && (machine.wantsConnection || [.connected, .connecting, .reconnecting, .needsSSO].contains(machine.status)) }
    var autoReconnectManaged: Bool { UserDefaults.standard.objectIsForced(forKey: "AutoReconnect") }

    func choose(_ host: String) {
        guard let host = Gateway.normalize(host) else { return }
        UserDefaults.standard.set(host, forKey: "LastSelectedGateway")
        send(.select(host))
    }
    func addGateway(_ input: String) {
        guard let host = Gateway.normalize(input) else { note = "Enter a DNS hostname, such as vpn.example.com."; return }
        if !gateways.contains(host) { gateways.append(host) }
        choose(host); note = "Gateway selection saved. Cisco still chooses the destination during sign-in."
    }

    func connect() {
        guard !busy else { return }
        send(.uiOwnsFlow(CiscoService.uiIsFrontmost()))
        send(.connect)
    }

    func disconnect() {
        reconnectIntent.cancel()
        generation += 1
        runner.cancel()
        operation?.cancel()
        busy = false
        send(.disconnect)
    }

    func cancelSignIn() { disconnect() }

    func reconnectNow() {
        guard !busy else { return }
        disconnect()
        reconnectIntent.start(now: now)
    }

    func setAutoReconnect(_ enabled: Bool) {
        guard !autoReconnectManaged else { return }
        UserDefaults.standard.set(enabled, forKey: "AutoReconnect")
        config = ConfigStore.read()
        machine.configuration = config
    }

    func recheck() {
        lastDiscovery = -.infinity
        Task { await refresh() }
    }

    func openCisco() { Task { if !(await CiscoService.openUI()) { send(.failed(.uiMissing)) } } }

    func openSelfService() {
        let paths = ["/Applications/Self Service.app", "/Applications/Self Service+.app", "/Applications/Jamf Self Service.app"]
        if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else { note = "Self Service is not installed. Ask your IT team to install Cisco Secure Client." }
    }

    func enableNotifications() {
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                note = allowed ? "Notifications enabled." : "Notifications are off. Enable them in System Settings."
            } catch { note = "Could not request notifications. Check System Settings." }
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copyDiagnostics() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let text = """
        Betterer Connect \(version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Cisco CLI installed: \(installation.cli != nil)
        Cisco agent running: \(installation.agentRunning)
        Cisco version: \(installation.version ?? "unknown")
        State: \(machine.status.rawValue)
        Selected gateway: \(machine.selectedGateway ?? "none")
        Reported server: \(sessionServer ?? "unknown")
        Reported group: \(sessionGroup ?? "unknown")
        Profile hosts found: \(!installation.hosts.isEmpty)
        Auto reconnect: \(config.autoReconnect)
        Last error: \(machine.lastError?.rawValue ?? "none")
        \(machine.lastError?.message ?? "")
        """
        copy(text)
        note = config.supportChannel.isEmpty ? "Diagnostics copied. Review the gateway hostname before sharing with IT." : "Diagnostics copied. Send to \(config.supportChannel)."
    }

    private func send(_ event: Event) {
        let before = machine.status
        let effects = machine.handle(event, now: now, jitter: Double.random(in: 0...1))
        if machine.status != before {
            if machine.status != .connected { sessionServer = nil; sessionGroup = nil }
            logger.info("state=\(self.machine.status.rawValue, privacy: .public) code=\(self.machine.lastError?.rawValue ?? "none", privacy: .public)")
        }
        for effect in effects { execute(effect) }
    }

    private func execute(_ effect: Effect) {
        switch effect {
        case .persist(let host): UserDefaults.standard.set(host, forKey: "LastUsedGateway")
        case .notify(let status): notify(status)
        case .openCisco: openCisco()
        case .connect(let host): runCommand(["connect", host], connecting: true)
        case .disconnect: runCommand(["disconnect"], connecting: false)
        }
    }

    private func runCommand(_ arguments: [String], connecting: Bool) {
        guard !demo, let cli = installation.cli else { return }
        generation += 1
        let ticket = generation
        busy = true
        operation = Task {
            guard ticket == generation, !Task.isCancelled else { return }
            let result = await runner.run(executable: cli, arguments: arguments, timeout: 25, stopAtInteractivePrompt: connecting)
            guard ticket == generation, !Task.isCancelled else { return }
            busy = false
            if !FileManager.default.isExecutableFile(atPath: cli) { send(.availability(false)); return }
            if connecting && CiscoParser.needsSSO(result.output) { send(.authRequired) }
            else if CiscoParser.isConflict(result.output) {
                // Resync first; if another client still owns a pending flow, latch handoff.
                await refresh()
                guard ticket == generation else { return }
                if connecting, machine.status != .connected { send(.authRequired) }
                if !connecting {
                    reconnectIntent.cancel()
                    note = "Cisco owns this connection. Use Disconnect or Cancel in Cisco's window. Automatic retries are stopped."
                    openCisco()
                }
                return
            }
            else if let error = result.failure { send(.failed(error)) }
            else if result.exitCode != 0 || CiscoParser.hasError(result.output) { send(.failed(CiscoParser.error(result.output))) }
            else {
                let state = CiscoParser.state(result.output)
                if state != .unknown { send(.observed(state)) }
            }
            await refresh()
            if !connecting, ticket == generation { finishReconnectIfReady() }
        }
    }

    private func refresh() async {
        guard !demo, !busy, !pollInProgress, !sleeping else { return }
        pollInProgress = true
        defer { pollInProgress = false }
        let ticket = generation
        if now - lastDiscovery > 30 {
            let detected = await CiscoService.detect(using: runner)
            guard ticket == generation else { return }
            installation = detected
            config = ConfigStore.read(); machine.configuration = config
            gateways = (config.gateways + installation.hosts + [machine.selectedGateway].compactMap { $0 }).reduce(into: []) {
                if !$0.contains($1) { $0.append($1) }
            }
            if machine.selectedGateway == nil, let first = config.preferredGateway ?? gateways.first { send(.select(first)) }
            send(.availability(installation.present))
            lastDiscovery = now
            if let cli = installation.cli, installation.present {
                let hosts = await runner.run(executable: cli, arguments: ["hosts"], timeout: 5)
                guard ticket == generation else { return }
                // The hosts command often returns display aliases, while XML supplies addresses.
                profileEmpty = installation.hosts.isEmpty && (hosts.exitCode != 0 || !CiscoParser.hasHostEntries(hosts.output))
                for host in CiscoParser.hosts(hosts.output) where !gateways.contains(host) { gateways.append(host) }
                if machine.selectedGateway == nil, let first = gateways.first { send(.select(first)) }
            } else { profileEmpty = installation.hosts.isEmpty }
        }
        guard installation.present, let cli = installation.cli else { return }
        send(.uiOwnsFlow(CiscoService.uiIsFrontmost()))
        let result = await runner.run(executable: cli, arguments: ["state"], timeout: 5)
        guard ticket == generation else { return }
        if let version = CiscoParser.version(result.output) { installation.version = version }
        if let error = result.failure { send(.pollFailed(error)) }
        else if result.exitCode != 0 || CiscoParser.hasError(result.output) { send(.pollFailed(CiscoParser.error(result.output))) }
        else { send(.observed(CiscoParser.state(result.output))) }
        if machine.status == .connected, sessionServer == nil, now - lastStats > 30 {
            lastStats = now
            let stats = await runner.run(executable: cli, arguments: ["stats"], timeout: 5)
            guard ticket == generation else { return }
            if stats.exitCode == 0, stats.failure == nil, !CiscoParser.hasError(stats.output) {
                let parsed = CiscoParser.statistics(stats.output)
                sessionServer = parsed.server; sessionGroup = parsed.group
                if let server = parsed.server { send(.confirmedGateway(server)) }
            }
        }
        finishReconnectIfReady()
    }

    private func finishReconnectIfReady() {
        guard !busy else { return }
        switch reconnectIntent.consume(status: machine.status, now: now) {
        case .connect: connect()
        case .timedOut: send(.failed(.timedOut))
        case .none: break
        }
    }

    private func startWatchers() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let signature = path.availableInterfaces.filter { path.usesInterfaceType($0.type) }.map { "\($0.type):\($0.name)" }.sorted().joined(separator: ",")
            Task { @MainActor [weak self] in
                guard let self else { return }
                let changed = self.pathSignature != nil && self.pathSignature != signature
                self.pathSignature = signature
                if !online { self.suspendCommands() }
                self.send(.network(online))
                if changed && online { self.send(.wake) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "betterer-connect.network"))
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendCommands()
                self?.sleeping = true; self?.send(.sleep)
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sleeping = false
                await self.refresh()
                self.send(.wake)
            }
        })
    }

    private func suspendCommands() {
        generation += 1
        reconnectIntent.cancel()
        operation?.cancel()
        runner.cancel()
        busy = false
    }

    private func notify(_ status: Status) {
        guard !demo else { return }
        let message: String
        switch status {
        case .connected: message = "Sign-in completed. Cisco reports an active VPN connection."
        case .needsSSO: message = "Finish sign-in in Cisco Secure Client. Select the gateway shown in Betterer Connect if prompted."
        case .ciscoMissing: message = SafeError.unavailable.message
        case .error: message = machine.lastError?.message ?? SafeError.commandFailed.message
        default: return
        }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Betterer Connect"; content.body = message
            try? await center.add(UNNotificationRequest(identifier: "connection-status", content: content, trigger: nil))
        }
    }
}
