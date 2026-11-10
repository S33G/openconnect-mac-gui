import Foundation

/// A manual disconnect-then-connect request survives stale state polls, but not cancellation.
public struct ReconnectIntent: Sendable {
    public enum Decision: Equatable, Sendable { case none, connect, timedOut }
    private var deadline: TimeInterval?
    public init() {}
    public mutating func start(now: TimeInterval) { deadline = now + 30 }
    public mutating func cancel() { deadline = nil }
    public mutating func consume(status: Status, now: TimeInterval) -> Decision {
        guard let deadline else { return .none }
        if [.error, .ciscoMissing, .offNetwork, .needsSSO].contains(status) { cancel(); return .none }
        if now >= deadline { cancel(); return .timedOut }
        if status == .disconnected { cancel(); return .connect }
        return .none
    }
}
