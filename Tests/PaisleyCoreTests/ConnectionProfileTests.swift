import XCTest
@testable import PaisleyCore

final class ConnectionProfileTests: XCTestCase {

    func testPasswordProfileRoundTrips() throws {
        let original = ConnectionProfile(
            nickname: "prod-box",
            host: "10.0.0.5",
            port: 2222,
            username: "deploy",
            authMethod: .password(keychainID: "kc-123")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConnectionProfile.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.nickname, "prod-box")
        XCTAssertEqual(decoded.host, "10.0.0.5")
        XCTAssertEqual(decoded.port, 2222)
        XCTAssertEqual(decoded.username, "deploy")
        guard case .password(let keychainID) = decoded.authMethod else {
            return XCTFail("expected .password auth method")
        }
        XCTAssertEqual(keychainID, "kc-123")
    }

    func testSSHKeyAuthRoundTrips() throws {
        let original = ConnectionProfile(
            nickname: "keyed", host: "h", username: "u",
            authMethod: .sshKey(path: "/home/u/.ssh/id_ed25519")
        )
        let decoded = try JSONDecoder().decode(
            ConnectionProfile.self, from: try JSONEncoder().encode(original))
        guard case .sshKey(let path) = decoded.authMethod else {
            return XCTFail("expected .sshKey auth method")
        }
        XCTAssertEqual(path, "/home/u/.ssh/id_ed25519")
    }

    func testDefaultPortIs22() {
        let p = ConnectionProfile(
            nickname: "n", host: "h", username: "u", authMethod: .password(keychainID: "x"))
        XCTAssertEqual(p.port, 22)
    }

    func testLocalProfileIsLocal() {
        let local = ConnectionProfile.localProfile(nickname: "shell")
        XCTAssertTrue(local.isLocal)
        XCTAssertEqual(local.nickname, "shell")
        XCTAssertEqual(local.host, "")
        XCTAssertEqual(local.port, 0)
    }

    func testRemoteProfileIsNotLocal() {
        let remote = ConnectionProfile(
            nickname: "n", host: "h", username: "u", authMethod: .password(keychainID: "x"))
        XCTAssertFalse(remote.isLocal)
    }
}
