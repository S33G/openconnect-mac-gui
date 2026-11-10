import Foundation

public enum Event: Sendable {
    case availability(Bool), network(Bool), uiOwnsFlow(Bool), select(String)
    case connect, disconnect, wake, sleep, tick, authRequired
    case observed(TunnelState), failed(SafeError), pollFailed(SafeError), confirmedGateway(String)
}

public enum Effect: Equatable, Sendable {
    case connect(String), disconnect, openCisco, persist(String), notify(Status)
}

/// No timers or subprocesses here: callers supply monotonic time and execute returned effects.
public struct ConnectionMachine: Sendable {
    public private(set) var status: Status = .ciscoMissing
    public private(set) var lastError: SafeError?
    public private(set) var selectedGateway: String?
    public private(set) var wantsConnection = false
    public private(set) var retryAt: TimeInterval?
    public private(set) var connectedSince: TimeInterval?
    public var attempts: Int { backoff.attempts }
    public private(set) var available = false
    public private(set) var online = true
    public var configuration: Configuration {
        didSet {
            backoff.maximum = configuration.maxBackoff
            if !configuration.autoReconnect, retryAt != nil {
                retryAt = nil
                if status == .reconnecting { status = .disconnected }
            }
        }
    }
    private var backoff: Backoff
    private var uiOwnsFlow = false
    private var ssoUntil: TimeInterval?
    private var commandUntil: TimeInterval?
    private var nativeUntil: TimeInterval?
    private var userStopped = false
    private var sleeping = false
    private var failureLatched = false

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.selectedGateway = configuration.preferredGateway
        self.backoff = Backoff(maximum: configuration.maxBackoff)
    }

    public mutating func handle(_ event: Event, now: TimeInterval, jitter: Double = 0.5) -> [Effect] {
        switch event {
        case .availability(let present):
            let changed = available != present
            available = present
            if !present {
                retryAt = nil; commandUntil = nil; nativeUntil = nil; ssoUntil = nil
                status = .ciscoMissing; lastError = .unavailable
                return changed ? [.notify(.ciscoMissing)] : []
            }
            if changed { status = online ? .disconnected : .offNetwork; lastError = nil; failureLatched = false }
        case .network(let reachable):
            let changed = online != reachable
            online = reachable
            guard available else { return [] }
            if !reachable {
                retryAt = nil; commandUntil = nil; nativeUntil = nil
                status = .offNetwork
            } else if changed {
                if ssoUntil != nil { status = .needsSSO }
                else if !failureLatched { status = .disconnected; return schedule(now, jitter) }
                else { status = .error }
            }
        case .uiOwnsFlow(let owns): uiOwnsFlow = owns
        case .select(let host):
            guard let host = Gateway.normalize(host) else { lastError = .noGateway; return [] }
            selectedGateway = host
            if lastError == .noGateway { lastError = nil; status = .disconnected }
        case .connect:
            guard available, online, !sleeping else { return [] }
            guard selectedGateway != nil else { return fail(.noGateway) }
            wantsConnection = true; userStopped = false; lastError = nil; failureLatched = false
            retryAt = nil; backoff = Backoff(maximum: configuration.maxBackoff)
            if ssoUntil != nil || uiOwnsFlow { return handoff(now) }
            if nativeUntil != nil { return [] }
            return start(now)
        case .disconnect:
            wantsConnection = false; userStopped = true
            retryAt = nil; ssoUntil = nil; commandUntil = nil; nativeUntil = nil
            backoff.reset(); lastError = nil; connectedSince = nil; failureLatched = false
            status = available ? (online ? .disconnected : .offNetwork) : .ciscoMissing
            return available ? [.disconnect] : []
        case .sleep:
            sleeping = true; retryAt = nil; commandUntil = nil
        case .wake:
            sleeping = false
            // A fresh poll gets first chance to observe Cisco's native reconnect.
            return schedule(now, jitter)
        case .authRequired:
            guard available, online, !userStopped else { return [] }
            return handoff(now)
        case .observed(let tunnel):
            guard available, online, !sleeping else { return [] }
            switch tunnel {
            case .connected:
                let wasConnected = status == .connected
                let hadAttempt = commandUntil != nil || ssoUntil != nil || retryAt != nil || backoff.attempts > 0
                let signedIn = ssoUntil != nil
                status = .connected; lastError = nil; failureLatched = false
                retryAt = nil; ssoUntil = nil; commandUntil = nil; nativeUntil = nil; backoff.reset()
                if !wasConnected { connectedSince = now }
                if !userStopped { wantsConnection = true }
                var effects: [Effect] = signedIn ? [.notify(.connected)] : []
                if !wasConnected, hadAttempt, !signedIn, !userStopped, let host = selectedGateway { effects.append(.persist(host)) }
                return effects
            case .connecting, .reconnecting:
                retryAt = nil
                if ssoUntil != nil { status = .needsSSO; return [] }
                if nativeUntil == nil { nativeUntil = now + 180 }
                status = tunnel == .connecting ? .connecting : .reconnecting
            case .disconnected:
                connectedSince = nil; nativeUntil = nil
                if ssoUntil != nil || commandUntil != nil { return [] }
                if status == .error { return [] }
                status = .disconnected
                return schedule(now, jitter)
            case .unknown:
                return fail(.unknownState)
            }
        case .failed(let error):
            if error == .operationCancelled { return [] }
            commandUntil = nil
            guard available, online else { return [] }
            if [.signingRejected, .unsupported, .unknownState, .uiMissing, .cancelled, .outputLimit].contains(error) {
                return fail(error)
            }
            if ssoUntil != nil { return fail(error) }
            lastError = error
            if wantsConnection && configuration.autoReconnect { return schedule(now, jitter) }
            return fail(error)
        case .pollFailed(let error):
            guard available, online, error != .operationCancelled else { return [] }
            return fail(error)
        case .confirmedGateway(let address):
            guard status == .connected, !userStopped, let host = Gateway.normalize(address),
                  host.rangeOfCharacter(from: .letters) != nil else { return [] }
            return [.persist(host)]
        case .tick:
            if let deadline = ssoUntil, now >= deadline { return fail(.ssoTimedOut) }
            guard available, online, !sleeping else { return [] }
            if let deadline = nativeUntil {
                if now >= deadline { return fail(.timedOut) }
                return []
            }
            if let deadline = commandUntil, now >= deadline {
                commandUntil = nil
                return handle(.failed(.timedOut), now: now, jitter: jitter)
            }
            guard let retryAt, now >= retryAt, wantsConnection, configuration.autoReconnect, ssoUntil == nil else { return [] }
            self.retryAt = nil
            if uiOwnsFlow { return handoff(now) }
            return start(now)
        }
        return []
    }

    private mutating func start(_ now: TimeInterval) -> [Effect] {
        guard let host = selectedGateway else { return fail(.noGateway) }
        status = backoff.attempts > 0 ? .reconnecting : .connecting
        commandUntil = now + 35
        return [.connect(host)]
    }

    private mutating func schedule(_ now: TimeInterval, _ jitter: Double) -> [Effect] {
        guard !failureLatched, status != .error, status != .connected, available, online, !sleeping, wantsConnection, configuration.autoReconnect,
              ssoUntil == nil, commandUntil == nil, nativeUntil == nil else { return [] }
        if retryAt != nil { status = .reconnecting; return [] }
        guard selectedGateway != nil else { return fail(.noGateway) }
        guard let delay = backoff.next(jitter: jitter) else { return fail(.exhausted) }
        retryAt = now + delay; status = .reconnecting
        return []
    }

    private mutating func handoff(_ now: TimeInterval) -> [Effect] {
        retryAt = nil; commandUntil = nil; nativeUntil = nil; lastError = nil; status = .needsSSO
        guard ssoUntil == nil else { return [.openCisco] }
        ssoUntil = now + 180
        return [.openCisco, .notify(.needsSSO)]
    }

    private mutating func fail(_ error: SafeError) -> [Effect] {
        let changed = status != .error || lastError != error
        lastError = error; status = .error
        failureLatched = true
        retryAt = nil; commandUntil = nil; ssoUntil = nil; nativeUntil = nil
        return changed ? [.notify(.error)] : []
    }
}
