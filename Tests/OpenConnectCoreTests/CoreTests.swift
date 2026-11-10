import XCTest
@testable import OpenConnectCore

final class CoreTests: XCTestCase {
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
        XCTAssertFalse(Configuration().runInBackground)
        XCTAssertTrue(Configuration(runInBackground: true).runInBackground)
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
