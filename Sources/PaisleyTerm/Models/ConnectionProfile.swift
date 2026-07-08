import Foundation

struct ConnectionProfile: Identifiable, Codable {
    var id: UUID = UUID()
    var nickname: String
    var host: String
    var port: Int = 22
    var username: String
    var authMethod: AuthMethod

    enum AuthMethod: Codable {
        case sshKey(path: String)
        case password(keychainID: String)
        case local
    }

    var isLocal: Bool {
        if case .local = authMethod { return true }
        return false
    }

    static func localProfile(nickname: String) -> ConnectionProfile {
        ConnectionProfile(nickname: nickname, host: "", port: 0, username: "", authMethod: .local)
    }
}
