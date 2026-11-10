import XCTest
@testable import BetterConnectCore

final class MachineTests: XCTestCase {
    func testHandoffDoesNotPersistAnUnverifiedSelectedGateway() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        _ = machine.handle(.authRequired, now: 1)
        XCTAssertFalse(machine.handle(.observed(.connected), now: 2).contains(.persist("vpn.example.com")))
        XCTAssertEqual(machine.handle(.confirmedGateway("other.example.com"), now: 3), [.persist("other.example.com")])
    }

    func testManualReconnectWaitsForConfirmedDisconnection() {
        var intent = ReconnectIntent()
        intent.start(now: 0)
        XCTAssertEqual(intent.consume(status: .connected, now: 1), .none)
        XCTAssertEqual(intent.consume(status: .reconnecting, now: 2), .none)
        XCTAssertEqual(intent.consume(status: .disconnected, now: 3), .connect)
        XCTAssertEqual(intent.consume(status: .disconnected, now: 4), .none)
        intent.start(now: 5)
        intent.cancel()
        XCTAssertEqual(intent.consume(status: .disconnected, now: 6), .none)
        intent.start(now: 10)
        XCTAssertEqual(intent.consume(status: .connected, now: 41), .timedOut)
    }
    func testNetworkRecoveryRetriesTransientErrorsButKeepsTerminalErrorsLatched() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        _ = machine.handle(.failed(.commandFailed), now: 1)
        _ = machine.handle(.network(false), now: 2)
        _ = machine.handle(.network(true), now: 3)
        XCTAssertEqual(machine.status, .reconnecting)
        XCTAssertEqual(machine.handle(.tick, now: 10), [.connect("vpn.example.com")])
        _ = machine.handle(.failed(.signingRejected), now: 11)
        _ = machine.handle(.network(false), now: 12)
        _ = machine.handle(.network(true), now: 13)
        XCTAssertEqual(machine.status, .error)
        XCTAssertEqual(machine.handle(.tick, now: 100), [])
    }
    func testSignInSuccessNotifiesButSilentReconnectDoesNot() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        _ = machine.handle(.authRequired, now: 1)
        XCTAssertTrue(machine.handle(.observed(.connected), now: 2).contains(.notify(.connected)))
        _ = machine.handle(.observed(.disconnected), now: 3)
        _ = machine.handle(.tick, now: 5)
        XCTAssertFalse(machine.handle(.observed(.connected), now: 6).contains(.notify(.connected)))
    }
    func testReadOnlyPollFailureNeverStartsConnection() {
        var machine = ready()
        _ = machine.handle(.observed(.connected), now: 0)
        _ = machine.handle(.pollFailed(.timedOut), now: 1)
        _ = machine.handle(.wake, now: 2)
        XCTAssertEqual(machine.handle(.tick, now: 100), [])
        XCTAssertEqual(machine.status, .error)
    }
    func testStaleDisconnectedPollDoesNotLaunchDuplicateConnect() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        _ = machine.handle(.observed(.disconnected), now: 0.5)
        XCTAssertEqual(machine.handle(.tick, now: 3), [])
        XCTAssertEqual(machine.status, .connecting)
    }

    func testWakeCannotRestartTerminalFailure() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        _ = machine.handle(.failed(.signingRejected), now: 1)
        _ = machine.handle(.wake, now: 2)
        XCTAssertEqual(machine.handle(.tick, now: 20), [])
        XCTAssertEqual(machine.status, .error)
    }

    func testTurningOffReconnectCancelsScheduledRetry() {
        var machine = ready()
        _ = machine.handle(.observed(.connected), now: 0)
        _ = machine.handle(.observed(.disconnected), now: 1)
        machine.configuration = Configuration(autoReconnect: false)
        XCTAssertNil(machine.retryAt)
        XCTAssertEqual(machine.status, .disconnected)
        XCTAssertEqual(machine.handle(.tick, now: 20), [])
    }

    private func ready(auto: Bool = true) -> ConnectionMachine {
        var machine = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"], autoReconnect: auto))
        _ = machine.handle(.availability(true), now: 0)
        _ = machine.handle(.network(true), now: 0)
        return machine
    }

    func testMissingClientAndOfflineNeverIssueConnect() {
        var machine = ConnectionMachine(configuration: Configuration(gateways: ["vpn.example.com"]))
        XCTAssertEqual(machine.handle(.connect, now: 0), [])
        XCTAssertEqual(machine.status, .ciscoMissing)
        _ = machine.handle(.availability(true), now: 0)
        _ = machine.handle(.network(false), now: 0)
        XCTAssertEqual(machine.handle(.connect, now: 0), [])
        XCTAssertEqual(machine.status, .offNetwork)
    }

    func testSuccessPersistsOnlyAfterConnectedAndDisconnectCancelsRetries() {
        var machine = ready()
        XCTAssertEqual(machine.handle(.connect, now: 0), [.connect("vpn.example.com")])
        XCTAssertEqual(machine.status, .connecting)
        XCTAssertTrue(machine.handle(.observed(.connected), now: 1).contains(.persist("vpn.example.com")))
        XCTAssertEqual(machine.status, .connected)
        XCTAssertEqual(machine.handle(.disconnect, now: 2), [.disconnect])
        _ = machine.handle(.observed(.disconnected), now: 3)
        XCTAssertEqual(machine.handle(.wake, now: 4), [])
        XCTAssertEqual(machine.handle(.tick, now: 100), [])
        XCTAssertFalse(machine.wantsConnection)
    }

    func testDropBackoffWaitsAndResetsOnSuccess() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        _ = machine.handle(.observed(.connected), now: 1)
        _ = machine.handle(.observed(.disconnected), now: 2)
        XCTAssertEqual(machine.status, .reconnecting)
        XCTAssertEqual(machine.handle(.tick, now: 3), [])
        XCTAssertEqual(machine.handle(.tick, now: 4), [.connect("vpn.example.com")])
        _ = machine.handle(.observed(.connected), now: 5)
        XCTAssertEqual(machine.attempts, 0)
    }

    func testSSOHandoffIsLatchedAcrossPollingAndNetworkChanges() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        XCTAssertEqual(machine.handle(.authRequired, now: 1), [.openCisco, .notify(.needsSSO)])
        XCTAssertEqual(machine.handle(.observed(.disconnected), now: 2), [])
        _ = machine.handle(.network(false), now: 3)
        _ = machine.handle(.network(true), now: 4)
        XCTAssertEqual(machine.handle(.tick, now: 50), [])
        XCTAssertEqual(machine.status, .needsSSO)
        _ = machine.handle(.tick, now: 182)
        XCTAssertEqual(machine.status, .error)
        XCTAssertEqual(machine.lastError, .ssoTimedOut)
    }

    func testNativeReconnectAndFrontmostCiscoAreObservedWithoutCLI() {
        var machine = ready()
        _ = machine.handle(.uiOwnsFlow(true), now: 0)
        XCTAssertEqual(machine.handle(.connect, now: 0), [.openCisco, .notify(.needsSSO)])
        var native = ready()
        _ = native.handle(.observed(.connected), now: 0)
        _ = native.handle(.observed(.reconnecting), now: 1)
        XCTAssertEqual(native.handle(.tick, now: 20), [])
        XCTAssertEqual(native.status, .reconnecting)
    }

    func testAutoReconnectDisabledStillAllowsManualConnection() {
        var machine = ready(auto: false)
        XCTAssertEqual(machine.handle(.connect, now: 0), [.connect("vpn.example.com")])
        _ = machine.handle(.observed(.connected), now: 1)
        _ = machine.handle(.observed(.disconnected), now: 2)
        XCTAssertEqual(machine.handle(.tick, now: 100), [])
        XCTAssertEqual(machine.status, .disconnected)
    }

    func testUnknownStateAndSigningErrorsDoNotTriggerReconnect() {
        var machine = ready()
        _ = machine.handle(.observed(.connected), now: 0)
        _ = machine.handle(.failed(.signingRejected), now: 1)
        XCTAssertEqual(machine.status, .error)
        XCTAssertEqual(machine.handle(.tick, now: 100), [])
        XCTAssertEqual(machine.lastError, .signingRejected)
    }

    func testRetryBudgetEndsAndPollsDoNotRestartIt() {
        var machine = ready()
        _ = machine.handle(.connect, now: 0)
        for index in 0..<6 {
            _ = machine.handle(.failed(.commandFailed), now: Double(index * 100))
            _ = machine.handle(.tick, now: Double(index * 100 + 99))
        }
        XCTAssertEqual(machine.status, .error)
        XCTAssertEqual(machine.lastError, .exhausted)
        _ = machine.handle(.observed(.disconnected), now: 700)
        XCTAssertEqual(machine.handle(.tick, now: 800), [])
    }
}
