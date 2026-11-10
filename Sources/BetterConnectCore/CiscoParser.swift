import Foundation

public enum CiscoParser {
    public struct Statistics: Sendable {
        public var server: String?
        public var group: String?
    }

    public static func statistics(_ text: String) -> Statistics {
        var result = Statistics()
        for line in text.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: CharacterSet(charactersIn: " >\t")).split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if key == "server address" { result.server = Gateway.normalize(value) }
            if ["tunnel group", "group"].contains(key),
               value.range(of: #"^[A-Za-z0-9_-]{1,80}$"#, options: .regularExpression) != nil {
                result.group = value
            }
        }
        return result
    }
    public static func hasHostEntries(_ text: String) -> Bool {
        if !hosts(text).isEmpty { return true }
        guard let section = text.range(of: "[hosts]:", options: .caseInsensitive) else { return false }
        return text[section.upperBound...].components(separatedBy: .newlines).contains {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("> ") && line.count > 2 && !line.hasPrefix(">>")
        }
    }
    // Cisco versions differ. Unrecognized output never implies a disconnected tunnel.
    public static func state(_ text: String) -> TunnelState {
        var result = TunnelState.unknown
        for line in text.components(separatedBy: .newlines) {
            let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: " >\t")).lowercased()
            guard cleaned.hasPrefix("state:") else { continue }
            let token = cleaned.dropFirst(6).trimmingCharacters(in: .whitespaces)
            result = TunnelState(rawValue: token) ?? .unknown
        }
        return result
    }

    public static func hosts(_ text: String) -> [String] {
        var hosts = [String]()
        for line in text.components(separatedBy: .newlines) {
            let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: " >\t"))
            let parts = cleaned.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, ["host", "host address", "hostaddress"].contains(parts[0].lowercased()),
                  let host = Gateway.normalize(String(parts[1])), !hosts.contains(host) else { continue }
            hosts.append(host)
        }
        return hosts
    }

    public static func error(_ text: String) -> SafeError {
        let text = text.lowercased()
        if text.contains("code signing requirements") { return .signingRejected }
        if text.contains("unknown command") || text.contains("invalid command") { return .unsupported }
        if text.contains("service is unavailable") || text.contains("cannot contact") { return .unavailable }
        if text.contains("cancelled") || text.contains("canceled") || text.contains("authentication failed") { return .cancelled }
        return .commandFailed
    }

    public static func needsSSO(_ text: String) -> Bool {
        let text = text.lowercased()
        return ["saml", "sign in", "sign-in", "authentication in the browser", "web authentication", "username:", "password:", "second password:", "group:"].contains(where: text.contains)
    }

    public static func isConflict(_ text: String) -> Bool {
        let text = text.lowercased()
        return ["already connected", "already in progress", "another application", "another client", "another cisco secure client application", "another anyconnect application"].contains(where: text.contains)
    }

    public static func hasError(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " >\t")).lowercased().hasPrefix("error:")
        }
    }

    public static func version(_ text: String) -> String? {
        guard let range = text.range(of: #"\b[0-9]{1,2}\.[0-9]{1,3}\.[0-9]{1,5}(?:\.[0-9]{1,5})?\b"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}
