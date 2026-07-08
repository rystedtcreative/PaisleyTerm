import SwiftUI

struct AgentContextMenu: View {
    @ObservedObject var session: SSHSession
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if session.profile.isLocal {
                localItems
            } else {
                switch session.connectionStatus {
                case .connected:
                    connectedItems
                case .disconnected, .error:
                    Button("Connect") { appState.connect(session: session) }
                case .connecting:
                    Text("Connecting…").foregroundColor(.secondary)
                }
            }

            Divider()

            Button("Remove", role: .destructive) {
                appState.removeProfile(id: session.id)
            }
        }
    }

    @ViewBuilder
    private var localItems: some View {
        agentMenu(for: .claudeCode)
        agentMenu(for: .openCode)
    }

    @ViewBuilder
    private var connectedItems: some View {
        agentMenu(for: .claudeCode)
        agentMenu(for: .openCode)

        Divider()

        Button("Disconnect") { appState.disconnect(session: session) }
    }

    @ViewBuilder
    private func agentMenu(for agentType: AgentType) -> some View {
        Menu(agentType.displayName) {
            Button("Install") {
                appState.installAgent(agentType, in: session)
            }
            Button("Add to PATH") {
                appState.addAgentToPath(agentType, in: session)
            }
            if session.activeAgent == agentType {
                Button("Stop \(agentType.displayName)") {
                    appState.stopAgent(in: session)
                }
            } else {
                Button("Launch") {
                    appState.launchAgent(agentType, in: session)
                }
            }
        }
    }
}
