import Foundation

public enum Status: String, Sendable {
    case dependenciesMissing, offNetwork, disconnected, permission, connecting, needsSSO, connected, reconnecting, disconnecting, error
}
public enum SafeError: String, Error, Sendable {
    case unavailable = "DEPENDENCIES_UNAVAILABLE"
    case commandFailed = "SESSION_FAILED"
    case timedOut = "COMMAND_TIMEOUT"
    case ssoTimedOut = "SIGN_IN_TIMEOUT"
    case cancelled = "AUTHENTICATION_FAILED"
    case noGateway = "NO_GATEWAY"
    case exhausted = "RETRIES_EXHAUSTED"
    case outputLimit = "OUTPUT_LIMIT"
    case operationCancelled = "OPERATION_CANCELLED"
    case permission = "ADMIN_PERMISSION_FAILED"
    case certificate = "CERTIFICATE_REJECTED"
    case stale = "SESSION_STATUS_STALE"
    case disconnectStuck = "DISCONNECT_UNCONFIRMED"
    public var message: String {
        switch self {
        case .unavailable: "Install OpenConnect and openconnect-sso, then re-check."
        case .commandFailed: "OpenConnect could not complete the session. Check the gateway and authentication group, then retry."
        case .timedOut: "The command did not respond in time."
        case .ssoTimedOut: "Sign-in did not finish within three minutes. Retry when ready."
        case .cancelled: "Sign-in was cancelled or rejected. Retry when ready."
        case .noGateway: "Choose a gateway or enter the hostname supplied by your IT team."
        case .exhausted: "Automatic reconnect stopped after five attempts. Retry when ready."
        case .outputLimit: "The command returned more output than expected."
        case .operationCancelled: "The operation was cancelled."
        case .permission: "Administrator access was not granted. Retry and complete the prompt in Terminal."
        case .certificate: "The VPN server certificate was rejected. Check the gateway with your IT team."
        case .stale: "Session status is unavailable. Check Terminal. A new session cannot start until teardown is confirmed."
        case .disconnectStuck: "Tunnel teardown is not confirmed. Check Terminal; a new session is blocked."
        }
    }
}
