import Foundation

public class ProfileStore {
    private let fileURL: URL

    /// - Parameter baseDirectory: parent directory under which a `PaisleyTerm`
    ///   folder holds `profiles.json`. Defaults to the platform Application
    ///   Support directory, preserving the original macOS behavior. Injectable
    ///   so tests (and, later, an XDG path on Linux) can point it elsewhere.
    public init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? Self.defaultBaseDirectory()
        let dir = base.appendingPathComponent("PaisleyTerm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
    }

    private static func defaultBaseDirectory() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
    }

    public func loadProfiles() -> [ConnectionProfile] {
        guard let data = try? Data(contentsOf: fileURL),
              let profiles = try? JSONDecoder().decode([ConnectionProfile].self, from: data)
        else { return [] }
        return profiles
    }

    public func saveProfiles(_ profiles: [ConnectionProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func addProfile(_ profile: ConnectionProfile) {
        var profiles = loadProfiles()
        profiles.append(profile)
        saveProfiles(profiles)
    }

    public func removeProfile(id: UUID) {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == id }
        saveProfiles(profiles)
    }
}
