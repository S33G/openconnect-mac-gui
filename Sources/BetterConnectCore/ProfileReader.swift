import Foundation

public struct ProfileSummary: Sendable {
    public var hosts: [String] = []
    public var autoReconnect: Bool?
    public var reconnectAfterResume: Bool?
    public var automaticVPNPolicy: Bool?
    public init() {}
}

public enum ProfileReader {
    public static func read(_ data: Data) -> ProfileSummary {
        guard data.count <= 1_048_576 else { return ProfileSummary() }
        let delegate = ProfileDelegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() ? delegate.result : ProfileSummary()
    }
}

private final class ProfileDelegate: NSObject, XMLParserDelegate {
    var result = ProfileSummary()
    var texts: [String] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        texts.append("")
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !texts.isEmpty { texts[texts.count - 1] += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = (texts.popLast() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "HostAddress":
            if let host = Gateway.normalize(text), !result.hosts.contains(host) { result.hosts.append(host) }
        case "AutoReconnect": result.autoReconnect = boolean(text)
        case "AutoReconnectBehavior": result.reconnectAfterResume = text == "ReconnectAfterResume"
        case "AutomaticVPNPolicy": result.automaticVPNPolicy = boolean(text)
        default: break
        }
    }
    private func boolean(_ text: String) -> Bool? {
        switch text.lowercased() { case "true": true; case "false": false; default: nil }
    }
}
