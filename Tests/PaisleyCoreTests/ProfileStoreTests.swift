import XCTest
@testable import PaisleyCore

final class ProfileStoreTests: XCTestCase {

    private func makeTempStore() throws -> (ProfileStore, URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("paisley-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return (ProfileStore(baseDirectory: base), base)
    }

    private func sampleProfile(_ nickname: String) -> ConnectionProfile {
        ConnectionProfile(
            nickname: nickname, host: "h", username: "u",
            authMethod: .password(keychainID: "kc-\(nickname)"))
    }

    func testLoadEmptyReturnsEmpty() throws {
        let (store, base) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertTrue(store.loadProfiles().isEmpty)
    }

    func testSaveThenLoadRoundTrips() throws {
        let (store, base) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let profiles = [sampleProfile("a"), sampleProfile("b")]
        store.saveProfiles(profiles)

        let loaded = store.loadProfiles()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.nickname), ["a", "b"])
        XCTAssertEqual(loaded.map(\.id), profiles.map(\.id))
    }

    func testAddProfileAppends() throws {
        let (store, base) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: base) }
        store.addProfile(sampleProfile("a"))
        store.addProfile(sampleProfile("b"))
        XCTAssertEqual(store.loadProfiles().map(\.nickname), ["a", "b"])
    }

    func testRemoveProfileByID() throws {
        let (store, base) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let keep = sampleProfile("keep")
        let drop = sampleProfile("drop")
        store.saveProfiles([keep, drop])

        store.removeProfile(id: drop.id)

        let loaded = store.loadProfiles()
        XCTAssertEqual(loaded.map(\.nickname), ["keep"])
    }

    func testPersistsAcrossStoreInstances() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("paisley-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        ProfileStore(baseDirectory: base).saveProfiles([sampleProfile("persisted")])
        // A fresh store over the same directory sees the written profiles.
        let reopened = ProfileStore(baseDirectory: base)
        XCTAssertEqual(reopened.loadProfiles().map(\.nickname), ["persisted"])
    }
}
