import AppKit
import BetterConnectCore

struct CiscoInstallation: Sendable {
    var cli: String?
    var agentRunning = false
    var version: String?
    var profiles = [ProfileSummary]()
    var present: Bool { cli != nil && agentRunning }
    var hosts: [String] { profiles.flatMap(\.hosts).reduce(into: []) { if !$0.contains($1) { $0.append($1) } } }
}

enum CiscoService {
    static let cliPaths = ["/opt/cisco/secureclient/bin/vpn", "/opt/cisco/anyconnect/bin/vpn"]
    static let appPaths = ["/Applications/Cisco/Cisco Secure Client.app", "/Applications/Cisco/Cisco AnyConnect Secure Mobility Client.app"]

    static func detect(using runner: ProcessRunner) async -> CiscoInstallation {
        var result = CiscoInstallation()
        result.cli = cliPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        let agent = await runner.run(executable: "/usr/bin/pgrep", arguments: ["-x", "vpnagentd"], timeout: 3)
        result.agentRunning = agent.exitCode == 0
        for directory in ["/opt/cisco/secureclient/vpn/profile", "/opt/cisco/anyconnect/profile"] {
            let files = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.fileSizeKey])) ?? []
            for file in files.prefix(32) where file.pathExtension.lowercased() == "xml" {
                guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_048_576,
                      let data = try? Data(contentsOf: file) else { continue }
                result.profiles.append(ProfileReader.read(data))
            }
        }
        for path in appPaths {
            if let version = Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                result.version = CiscoParser.version(version)
            }
        }
        return result
    }

    @MainActor static func uiIsFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return app.bundleURL.map { appPaths.contains($0.path) } == true || app.executableURL?.lastPathComponent == "vpnui"
    }

    @MainActor static func openUI() async -> Bool {
        guard let path = appPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return false }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch { return false }
    }
}

@MainActor enum ConfigStore {
    static func read() -> Configuration {
        // UserDefaults honors forced managed preferences in the app's bundle domain.
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
