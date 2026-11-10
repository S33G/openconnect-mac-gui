import Foundation

public enum TunnelState: String, Sendable { case connected, disconnected, connecting, reconnecting, unknown }
public enum Status: String, Sendable { case ciscoMissing, offNetwork, disconnected, connecting, needsSSO, connected, reconnecting, error }

public enum SafeError: String, Error, Sendable {
    case signingRejected = "CISCO_SIGNING_REJECTED"
    case unavailable = "CISCO_UNAVAILABLE"
    case unsupported = "CLI_UNSUPPORTED"
    case unknownState = "STATE_UNKNOWN"
    case commandFailed = "COMMAND_FAILED"
    case timedOut = "COMMAND_TIMEOUT"
    case ssoTimedOut = "SSO_TIMEOUT"
    case cancelled = "SIGN_IN_CANCELLED"
    case noGateway = "NO_GATEWAY"
    case exhausted = "RETRIES_EXHAUSTED"
    case uiMissing = "CISCO_UI_MISSING"
    case outputLimit = "OUTPUT_LIMIT"
    case operationCancelled = "OPERATION_CANCELLED"
    public var message: String {
        switch self {
        case .signingRejected: "Cisco rejected this client's code signature. Open Cisco or ask IT to repair its installation."
        case .unavailable: "Cisco Secure Client or its VPN service is unavailable. Open Self Service or contact IT."
        case .unsupported: "This Cisco version does not support the requested command. Open Cisco to check the connection."
        case .unknownState: "Cisco returned an unrecognized state. Open Cisco to check the connection."
        case .commandFailed: "Cisco could not complete the command. Open Cisco for details."
        case .timedOut: "Cisco did not respond in time. Open Cisco, then re-check."
        case .ssoTimedOut: "Sign-in did not finish within three minutes. Try again in Cisco."
        case .cancelled: "Sign-in was cancelled or rejected. Try again in Cisco."
        case .noGateway: "Choose a gateway or enter the hostname provided by your IT team."
        case .exhausted: "Automatic reconnect stopped after five attempts. Check Cisco, then retry."
        case .uiMissing: "Cisco's app could not be opened. Install or repair Cisco through your IT team."
        case .outputLimit: "Cisco returned more output than expected. Open Cisco for details."
        case .operationCancelled: "The operation was cancelled."
        }
    }
}
