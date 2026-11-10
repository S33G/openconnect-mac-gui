import XCTest
@testable import BetterConnectCore

final class MachineTests: XCTestCase {
    func testAuthenticationIsNotConnectionAndStopRequiresConfirmation() {
        var m = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"]))
        m.setAvailable(true)
        XCTAssertTrue(m.begin(now: 0))
        m.observe(phase: "authorizing", finished: false, now: 1)
        XCTAssertNotEqual(m.status, .connected)
        m.observe(phase: "connected", finished: false, now: 2)
        XCTAssertEqual(m.status, .connected)
        m.requestStop()
        m.observe(phase: "connected", finished: false, now: 3)
        XCTAssertEqual(m.status, .disconnecting)
        XCTAssertFalse(m.begin(now: 3))
        m.observe(phase: "stopped", finished: true, now: 4)
        XCTAssertEqual(m.status, .disconnected)
        XCTAssertFalse(m.sessionActive)
    }
    func testStaleHeartbeatNeverReleasesAnOwnedSession() {
        var m = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"]))
        m.setAvailable(true)
        XCTAssertTrue(m.begin(now: 0))
        m.stale()
        XCTAssertEqual(m.status, .error)
        XCTAssertTrue(m.sessionActive)
        XCTAssertFalse(m.begin(now: 100))
    }
    func testRetryOnlyAfterPreviouslyEstablishedTunnelAndConfirmedExit() {
        var m = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"]))
        m.setAvailable(true)
        XCTAssertTrue(m.begin(now: 0))
        m.observe(phase: "session_failed", finished: true, now: 1)
        XCTAssertNil(m.retryAt)
        XCTAssertTrue(m.begin(now: 2))
        m.observe(phase: "connected", finished: false, now: 3)
        m.observe(phase: "session_failed", finished: true, now: 4)
        XCTAssertNotNil(m.retryAt)
        m.requestStop()
        XCTAssertNil(m.retryAt)
    }
    func testStableConnectionResetsRetryBudget() {
        var m = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"]))
        m.setAvailable(true)
        _ = m.begin(now: 0)
        for cycle in 0..<8 {
            let t = Double(cycle * 50)
            m.observe(phase: "connected", finished: false, now: t + 1)
            m.observe(phase: "connected", finished: false, now: t + 32)
            m.observe(phase: "session_failed", finished: true, now: t + 33)
            XCTAssertEqual(m.attempts, 1)
            XCTAssertTrue(m.begin(now: t + 40, retry: true))
        }
    }
    func testCertificateFailureDoesNotRetry() {
        var m = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"]))
        m.setAvailable(true)
        _ = m.begin(now: 0)
        m.observe(phase: "connected", finished: false, now: 1)
        m.observe(phase: "certificate_failed", finished: false, now: 2)
        m.observe(phase: "certificate_failed", finished: true, now: 3)
        XCTAssertNil(m.retryAt)
        XCTAssertEqual(m.lastError, .certificate)
    }
}
