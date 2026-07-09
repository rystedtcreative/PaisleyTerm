import Foundation
import Combine
import SwiftUI
import PaisleyCore

enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected:     return "disconnected"
        case .connecting:       return "connecting…"
        case .connected:        return "connected"
        case .error(let msg):   return "error: \(msg)"
        }
    }

    // Dracula palette — inlined so this file has no cross-directory dependencies.
    var draculaColor: Color {
        switch self {
        case .disconnected: return Color(.sRGB, red: 0.384, green: 0.447, blue: 0.643) // #6272a4
        case .connecting:   return Color(.sRGB, red: 0.945, green: 0.980, blue: 0.549) // #f1fa8c
        case .connected:    return Color(.sRGB, red: 0.314, green: 0.980, blue: 0.482) // #50fa7b
        case .error:        return Color(.sRGB, red: 1.000, green: 0.333, blue: 0.333) // #ff5555
        }
    }
}

@MainActor
class SSHSession: ObservableObject, Identifiable {
    let id: UUID
    let profile: ConnectionProfile

    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var activeAgent: AgentType? = nil
    @Published var agentStatus: AgentStatus = .inactive
    @Published var lastActivityMessage: String? = nil

    let outputSubject = PassthroughSubject<Data, Never>()
    let inputSubject  = PassthroughSubject<Data, Never>()

    init(profile: ConnectionProfile) {
        self.id = profile.id
        self.profile = profile
        if profile.isLocal {
            self.connectionStatus = .connected
        }
    }
}
