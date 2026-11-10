import XCTest
@testable import BetterConnectCore

final class ProfileTests: XCTestCase {
    func testProfileExtractsOnlyValidatedHostsAndPolicyFlags() {
        let xml = """
        <AnyConnectProfile><ClientInitialization><AutoReconnect>true<AutoReconnectBehavior>ReconnectAfterResume</AutoReconnectBehavior></AutoReconnect><AutomaticVPNPolicy>false</AutomaticVPNPolicy></ClientInitialization><ServerList><HostEntry><HostName>Office</HostName><HostAddress>vpn.example.com</HostAddress></HostEntry><HostEntry><HostAddress>https://user:pass@bad.example.com</HostAddress></HostEntry></ServerList></AnyConnectProfile>
        """
        let result = ProfileReader.read(Data(xml.utf8))
        XCTAssertEqual(result.hosts, ["vpn.example.com"])
        XCTAssertEqual(result.autoReconnect, true)
        XCTAssertEqual(result.reconnectAfterResume, true)
        XCTAssertEqual(result.automaticVPNPolicy, false)
    }

    func testMalformedAndExternalEntityProfilesAreNotTrusted() {
        XCTAssertEqual(ProfileReader.read(Data("<bad".utf8)).hosts, [])
        let xml = "<!DOCTYPE x [<!ENTITY ext SYSTEM 'file:///etc/passwd'>]><AnyConnectProfile><HostAddress>&ext;</HostAddress></AnyConnectProfile>"
        XCTAssertEqual(ProfileReader.read(Data(xml.utf8)).hosts, [])
    }
}
