import Foundation

class ProfileStore {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("PaisleyTerm")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
    }

    func loadProfiles() -> [ConnectionProfile] {
        guard let data = try? Data(contentsOf: fileURL),
              let profiles = try? JSONDecoder().decode([ConnectionProfile].self, from: data)
        else { return [] }
        return profiles
    }

    func saveProfiles(_ profiles: [ConnectionProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func addProfile(_ profile: ConnectionProfile) {
        var profiles = loadProfiles()
        profiles.append(profile)
        saveProfiles(profiles)
    }

    func removeProfile(id: UUID) {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == id }
        saveProfiles(profiles)
    }
}
