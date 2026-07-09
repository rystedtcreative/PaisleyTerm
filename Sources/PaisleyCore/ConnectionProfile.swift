import Foundation

public struct ConnectionProfile: Identifiable, Codable {
    public var id: UUID = UUID()
    public var nickname: String
    public var host: String
    public var port: Int = 22
    public var username: String
    public var authMethod: AuthMethod

    public enum AuthMethod: Codable {
        case sshKey(path: String)
        case password(keychainID: String)
        case local
    }

    public init(
        id: UUID = UUID(),
        nickname: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod
    ) {
        self.id = id
        self.nickname = nickname
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
    }

    public var isLocal: Bool {
        if case .local = authMethod { return true }
        return false
    }

    public static func localProfile(nickname: String) -> ConnectionProfile {
        ConnectionProfile(nickname: nickname, host: "", port: 0, username: "", authMethod: .local)
    }
}
