import Foundation

public enum Gateway {
    /// Hostnames only. No CLI options, credentials, ports, paths, or query strings.
    public static func normalize(_ value: String) -> String? {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("https://") { host.removeFirst(8) }
        guard host.count <= 253, host.contains("."),
              host.range(of: #"^[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?$"#, options: .regularExpression) != nil else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else { return nil }
        return host
    }
}

public struct Configuration: Sendable {
    public let gateways: [String]
    public let preferredGateway: String?
    public let runInBackground: Bool
    public let autoReconnect: Bool
    public let maxBackoff: Double
    public let preferredGroup: String
    public let supportChannel: String

    public init(gateways: [String] = [], defaultGateway: String? = nil, lastUsed: String? = nil, lastSelected: String? = nil,
                autoReconnect: Bool = true, runInBackground: Bool = false, maxBackoff: Double = 300,
                preferredGroup: String = "", supportChannel: String = "") {
        let defaultHost = defaultGateway.flatMap(Gateway.normalize)
        let last = lastUsed.flatMap(Gateway.normalize)
        let selected = lastSelected.flatMap(Gateway.normalize)
        var ordered = [String]()
        for host in gateways.compactMap(Gateway.normalize) + [defaultHost, last, selected].compactMap({ $0 }) {
            if !ordered.contains(host) { ordered.append(host) }
        }
        self.gateways = ordered
        self.preferredGateway = defaultHost ?? selected ?? last ?? ordered.first
        self.autoReconnect = autoReconnect
        self.runInBackground = runInBackground
        self.maxBackoff = maxBackoff.isFinite && maxBackoff >= 2 ? min(maxBackoff, 3600) : 300
        self.preferredGroup = String(preferredGroup.prefix(80))
        self.supportChannel = String(supportChannel.prefix(200))
    }
}

public struct Backoff: Sendable {
    public private(set) var attempts = 0
    public var maximum: Double
    public init(maximum: Double = 300) { self.maximum = maximum }
    public mutating func next(jitter: Double) -> Double? {
        guard attempts < 5 else { return nil }
        let base = 2 * pow(2, Double(attempts))
        attempts += 1
        return min(maximum, base * (0.8 + min(1, max(0, jitter)) * 0.4))
    }
    public mutating func reset() { attempts = 0 }
}
