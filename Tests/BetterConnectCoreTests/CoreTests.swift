import XCTest
@testable import BetterConnectCore

final class CoreTests: XCTestCase {
    func testStatisticsExposeOnlyValidatedServerAndGroup() {
        let stats = CiscoParser.statistics("Username: private@example.com\nServer Address: vpn.example.com\nTunnel Group: STAFF-ACCESS\nSession Token: secret")
        XCTAssertEqual(stats.server, "vpn.example.com")
        XCTAssertEqual(stats.group, "STAFF-ACCESS")
        let untrusted = CiscoParser.statistics("Server Address: https://user:pass@vpn.example.com\nTunnel Group: Bearer secret token")
        XCTAssertNil(untrusted.server)
        XCTAssertNil(untrusted.group)
    }
    func testStateParserOnlyTrustsExactStateLinesAndUsesLatest() {
        XCTAssertEqual(CiscoParser.state("VPN Connected to something\nUsername: Connected"), .unknown)
        XCTAssertEqual(CiscoParser.state("  >> state: Disconnected\n  >> state: Connected"), .connected)
        XCTAssertEqual(CiscoParser.state(" >> state: Reconnecting"), .reconnecting)
        XCTAssertEqual(CiscoParser.state(" >> state: Not Connected"), .unknown)
        XCTAssertEqual(CiscoParser.state(" >> state: Disconnected"), .disconnected)
    }

    func testOnlyAllowlistedErrorsEscapeTheParser() {
        XCTAssertEqual(CiscoParser.error("error: Application did not meet code signing requirements."), .signingRejected)
        XCTAssertEqual(CiscoParser.error("Unknown command: state"), .unsupported)
        XCTAssertEqual(CiscoParser.error("password=secret token=123 user@corp.example"), .commandFailed)
        XCTAssertTrue(CiscoParser.needsSSO("Please complete authentication in the browser"))
        XCTAssertTrue(CiscoParser.needsSSO("Username:"))
        XCTAssertFalse(CiscoParser.needsSSO("Connected"))
        XCTAssertTrue(CiscoParser.isConflict("Connection is already in progress"))
        XCTAssertTrue(CiscoParser.isConflict("  >> error: Connect capability is unavailable. Another Cisco Secure Client application acquired it."))
        XCTAssertTrue(CiscoParser.hasError(" >> state: Disconnected\n >> error: Connect capability is unavailable."))
        XCTAssertFalse(CiscoParser.hasError(" >> state: Connected\nerror count: 0"))
    }

    func testHostsParserDoesNotTreatBannersOrURLsWithSecretsAsHosts() {
        XCTAssertEqual(CiscoParser.hosts("Cisco Secure Client\nVPN> hosts\n > host: vpn.example.com\n > host: backup.example.com\n > host: https://user:secret@vpn.example.com/path?token=x"), ["vpn.example.com", "backup.example.com"])
        XCTAssertEqual(CiscoParser.hosts("No hosts available."), [])
        XCTAssertTrue(CiscoParser.hasHostEntries("    [hosts]:\n\n    > Example Office\n    > Example Cloud\n"))
        XCTAssertFalse(CiscoParser.hasHostEntries("    [hosts]:\n\nVPN>"))
        XCTAssertFalse(CiscoParser.hasHostEntries(" >> state: Disconnected\nVPN>"))
    }

    func testGatewayValidationRejectsOptionsCredentialsAndPaths() {
        for invalid in ["-s", "vpn.example.com\nconnect evil.com", "https://user:pass@vpn.example.com", "vpn.example.com/path", "foo", "vpn..example.com", "a;whoami.com"] {
            XCTAssertNil(Gateway.normalize(invalid), invalid)
        }
        XCTAssertEqual(Gateway.normalize(" VPN.Example.com "), "vpn.example.com")
        XCTAssertEqual(Gateway.normalize("https://vpn.example.com"), "vpn.example.com")
    }

    func testConfigurationKeepsManagedOrderAndBoundsInvalidValues() {
        let config = Configuration(gateways: ["b.example.com", "a.example.com", "b.example.com", "-x"], defaultGateway: "d.example.com", lastUsed: "c.example.com", autoReconnect: false, maxBackoff: -1)
        XCTAssertEqual(config.gateways, ["b.example.com", "a.example.com", "d.example.com", "c.example.com"])
        XCTAssertEqual(config.preferredGateway, "d.example.com")
        XCTAssertFalse(config.autoReconnect)
        XCTAssertEqual(config.maxBackoff, 300)
        XCTAssertEqual(Configuration().gateways, [])
        XCTAssertNil(Configuration().preferredGateway)
        XCTAssertEqual(Configuration(lastUsed: "old.example.com", lastSelected: "new.example.com").preferredGateway, "new.example.com")
        XCTAssertEqual(Configuration(lastUsed: "old.example.com", lastSelected: "-invalid").preferredGateway, "old.example.com")
    }

    func testBackoffJitterCapAndFiniteAttempts() {
        var backoff = Backoff(maximum: 5)
        XCTAssertEqual(backoff.next(jitter: 0), 1.6)
        XCTAssertEqual(backoff.next(jitter: 1) ?? 0, 4.8, accuracy: 0.000001)
        XCTAssertEqual(backoff.next(jitter: 1), 5)
        _ = backoff.next(jitter: 1)
        _ = backoff.next(jitter: 1)
        XCTAssertNil(backoff.next(jitter: 1))
        backoff.reset()
        XCTAssertEqual(backoff.next(jitter: 0.5), 2)
    }
}
