import AppKit
import Darwin
import BetterConnectCore

struct OpenConnectInstallation {
    var openconnect: String?
    var python: String?
    var present: Bool { openconnect != nil && python != nil }
    static func detect() -> Self {
        let fm = FileManager.default
        let oc = ["/opt/homebrew/bin/openconnect", "/usr/local/bin/openconnect"].first(where: fm.isExecutableFile)
        let python = ["/opt/homebrew/bin/python3.11", "/usr/local/bin/python3.11", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first(where: fm.isExecutableFile)
        return Self(openconnect: oc, python: python)
    }
}

struct SessionRequest: Codable {
    let sessionID: String
    let host: String
    let group: String
    let openconnect: String
    let autoReconnect: Bool
    let bootID: String?
}
struct SessionStatus: Decodable {
    let sessionID: String
    let phase: String
    let updatedAt: Double
    let finished: Bool
}

@MainActor final class OpenConnectSession {
    let root: URL
    let request: SessionRequest
    var lastStatus: SessionStatus?
    static var sessionsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Betterer Connect/Sessions", isDirectory: true)
    }
    init(root: URL, request: SessionRequest) { self.root = root; self.request = request }
    static func bootIdentity() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1, size < 128 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let result = bytes.withUnsafeMutableBytes { buffer in
            sysctlbyname("kern.bootsessionuuid", buffer.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return nil }
        let value = String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        return UUID(uuidString: value)?.uuidString

    }
    static func recover() -> OpenConnectSession? {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: sessionsRoot, includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("request.json")),
                  let request = try? JSONDecoder().decode(SessionRequest.self, from: data) else { continue }
            if let previousBoot = request.bootID, let currentBoot = bootIdentity(), previousBoot != currentBoot {
                try? fm.removeItem(at: folder)
                continue
            }
            let session = OpenConnectSession(root: folder, request: request)
            let status = session.read()
            if status?.finished == true { try? fm.removeItem(at: folder); continue }
            return session
        }
        return nil
    }
    static func create(installation: OpenConnectInstallation, host: String, group: String, automatic: Bool) throws -> OpenConnectSession {
        guard let oc = installation.openconnect, let python = installation.python,
              let bridge = Bundle.main.url(forResource: "session_bridge", withExtension: "py") else { throw SafeError.unavailable }
        let request = SessionRequest(sessionID: UUID().uuidString, host: host, group: group, openconnect: oc, autoReconnect: automatic, bootID: bootIdentity())
        let root = sessionsRoot.appendingPathComponent(request.sessionID, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessionsRoot.path)
        let session = OpenConnectSession(root: root, request: request)
        var completed = false
        defer { if !completed { session.cleanup() } }
        try session.write(try JSONEncoder().encode(request), name: "request.json")
        let launch = "#!/bin/sh\nexec \(quote(python)) \(quote(bridge.path)) \(quote(root.path))\n"
        try session.write(Data(launch.utf8), name: "Launch.command")
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("Launch.command").path)
        session.heartbeat()
        completed = true
        return session
    }
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    func launch() async throws {
        _ = try await NSWorkspace.shared.open([root.appendingPathComponent("Launch.command")],
             withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
    }
    func write(_ data: Data, name: String) throws {
        let target = root.appendingPathComponent(name)
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    func heartbeat() { try? write(Data(), name: "owner") }
    func stop() {
        try? write(Data(), name: "stop")
        // Atomic claim excludes both a running bridge and a delayed Terminal launch.
        if Darwin.mkdir(root.appendingPathComponent("claimed").path, 0o700) == 0 {
            let value: [String: Any] = ["sessionID": request.sessionID, "phase": "stopped", "finished": true, "updatedAt": Date().timeIntervalSince1970]
            if let data = try? JSONSerialization.data(withJSONObject: value) { try? write(data, name: "status.json") }
        }
    }
    func read() -> SessionStatus? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("status.json")), data.count < 4096,
              let value = try? JSONDecoder().decode(SessionStatus.self, from: data), value.sessionID == request.sessionID else { return nil }
        lastStatus = value
        return value
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@MainActor enum ConfigStore {
    static func read() -> Configuration {
        let defaults = UserDefaults.standard
        return Configuration(
            gateways: defaults.stringArray(forKey: "GatewayList") ?? [],
            defaultGateway: defaults.string(forKey: "DefaultGateway"),
            lastUsed: defaults.string(forKey: "LastUsedGateway"),
            lastSelected: defaults.string(forKey: "LastSelectedGateway"),
            autoReconnect: defaults.object(forKey: "AutoReconnect") == nil ? true : defaults.bool(forKey: "AutoReconnect"),
            maxBackoff: (defaults.object(forKey: "MaxBackoffSeconds") as? NSNumber)?.doubleValue ?? 300,
            preferredGroup: defaults.string(forKey: "PreferredGroup") ?? "",
            supportChannel: defaults.string(forKey: "SupportChannel") ?? ""
        )
    }
}
