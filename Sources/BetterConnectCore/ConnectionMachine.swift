import Foundation

public struct ConnectionMachine: Sendable {
    public var configuration: Configuration
    public private(set) var status: Status = .dependenciesMissing
    public private(set) var available = false
    public private(set) var online = true
    public private(set) var sessionActive = false
    public private(set) var wantsConnection = false
    public var selectedGateway: String?
    public private(set) var lastError: SafeError?
    public private(set) var connectedSince: Double?
    public private(set) var retryAt: Double?
    public var attempts: Int { backoff.attempts }
    private var backoff: Backoff
    private var stopping = false
    private var established = false
    private var retryEligible = false
    public init(configuration: Configuration) {
        self.configuration = configuration
        selectedGateway = configuration.preferredGateway
        backoff = Backoff(maximum: configuration.maxBackoff)
    }
    public mutating func setAvailable(_ value: Bool) {
        available = value
        if !sessionActive && retryAt == nil && lastError == nil { status = !value ? .dependenciesMissing : online ? .disconnected : .offNetwork }
    }
    public mutating func setNetwork(_ value: Bool) {
        online = value
        if !value && !stopping { status = .offNetwork }
        else if !sessionActive && lastError == nil { status = available ? .disconnected : .dependenciesMissing }
    }
    public mutating func begin(now: Double, retry: Bool = false) -> Bool {
        guard available, online, !sessionActive else { return false }
        guard selectedGateway != nil else { fail(.noGateway); return false }
        if !retry { backoff.reset(); retryEligible = false }
        retryAt = nil; lastError = nil; connectedSince = nil
        sessionActive = true; wantsConnection = true; stopping = false; established = false
        status = .permission
        return true
    }
    public mutating func requestStop() {
        wantsConnection = false; retryAt = nil; backoff.reset(); retryEligible = false
        stopping = sessionActive
        if sessionActive { status = .disconnecting }
        else { lastError = nil; status = available ? (online ? .disconnected : .offNetwork) : .dependenciesMissing }
    }
    public mutating func fail(_ error: SafeError) { lastError = error; status = .error }
    public mutating func launchFailed() {
        sessionActive = false; wantsConnection = false; retryAt = nil; fail(.commandFailed)
    }
    public mutating func stale() { fail(.stale) }
    public mutating func observe(phase: String, finished: Bool, now: Double) {
        guard sessionActive else { return }
        let failure: SafeError? = switch phase {
        case "certificate_failed": .certificate
        case "authentication_failed": .cancelled
        case "permission_failed": .permission
        case "sign_in_timeout": .ssoTimedOut
        case "disconnect_stuck": .disconnectStuck
        case "session_failed": .commandFailed
        default: nil
        }
        if finished {
            sessionActive = false; connectedSince = nil
            if stopping || !wantsConnection {
                stopping = false; lastError = nil; status = online ? .disconnected : .offNetwork
                return
            }
            if (established || retryEligible) && configuration.autoReconnect && (failure == nil || failure == .commandFailed) {
                retryEligible = true
                if let delay = backoff.next(jitter: 0.5) {
                    retryAt = now + delay; status = online ? .reconnecting : .offNetwork; lastError = nil
                    return
                }
                fail(.exhausted)
            } else { fail(failure ?? .commandFailed) }
            wantsConnection = false
            return
        }
        if let failure { fail(failure); return }
        if stopping { status = .disconnecting; return }
        lastError = nil
        if !online { status = .offNetwork; return }
        switch phase {
        case "permission": status = .permission
        case "needs_sso": status = .needsSSO
        case "authorizing", "connecting": status = .connecting
        case "connected":
            if connectedSince == nil { connectedSince = now }
            if let since = connectedSince, now - since >= 30 { backoff.reset(); retryEligible = false }
            established = true; status = .connected
        case "reconnecting": connectedSince = nil; status = .reconnecting
        case "disconnecting": status = .disconnecting
        default: break
        }
    }
}
