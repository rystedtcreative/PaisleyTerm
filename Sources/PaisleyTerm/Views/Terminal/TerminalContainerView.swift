import SwiftUI
import PaisleyCore

// MARK: - Container

struct TerminalContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // Full-bleed frosted glass behind the card so the margins around it blur the
            // desktop instead of showing it through the transparent window.
            DraculaVibrancyBackground()

            Group {
                if appState.selectedSessionID == nil {
                    DashboardView()
                } else {
                    // All session views are kept alive in a ZStack so the NSView/terminal buffer
                    // is never destroyed when switching sessions. Only the selected session is
                    // visible and interactive; the rest are hidden and block no input.
                    ZStack {
                        ForEach(appState.sessions) { session in
                            let selected = session.id == appState.selectedSessionID
                            SessionTerminalView(session: session, isSelected: selected)
                                .opacity(selected ? 1 : 0)
                                .allowsHitTesting(selected)
                        }
                    }
                }
            }
            // Float the detail pane as a glass card matching the Liquid Glass sidebar.
            .padding(detailCardInsets)
        }
    }
}

// MARK: - Dashboard (empty state)

private struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    private var connectedCount: Int {
        appState.sessions.filter {
            if case .connected = $0.connectionStatus { return true }
            return false
        }.count
    }

    private var agentCount: Int {
        appState.sessions.filter { $0.activeAgent != nil }.count
    }

    private var activeAgentSessions: [SSHSession] {
        appState.sessions.filter { $0.activeAgent != nil }
    }

    var body: some View {
        ZStack {
            DraculaVibrancyBackground(cardStyle: true)

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 40)

                    // Header: sparkle logo + app name
                    dashboardHeader

                    // Stats row: sessions / active / agents
                    statsRow

                    // Active agent cards (only when agents are running)
                    if !activeAgentSessions.isEmpty {
                        activeAgentsSection
                    }

                    // Footer: add connection CTA
                    addConnectionButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Header

    private var dashboardHeader: some View {
        HStack(spacing: 8) {
            Text("✦")
                .font(.firaCodeSemiBold(24))
                .foregroundColor(.draculaPurple)

            Text("PaisleyTerm")
                .font(.firaCodeSemiBold(22))
                .foregroundColor(.draculaFg)
        }
    }

    // MARK: Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            StatCard(value: "\(appState.sessions.count)", label: "Sessions")
            StatCard(value: "\(connectedCount)",          label: "Active")
            StatCard(value: "\(agentCount)",              label: "Agents")
        }
        .frame(maxWidth: 420)
    }

    // MARK: Active agents section

    private var activeAgentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Agents".uppercased())
                .font(.firaCode(11))
                .tracking(1.2)
                .foregroundColor(.draculaComment)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                ForEach(activeAgentSessions) { session in
                    ActiveAgentCard(session: session)
                        .onTapGesture {
                            appState.selectedSessionID = session.id
                        }
                }
            }
        }
        .frame(maxWidth: 420)
    }

    // MARK: Add connection button

    private var addConnectionButton: some View {
        Button {
            appState.showingAddConnection = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add Connection")
                    .font(.firaCodeMedium(13))
                Text("⌘N")
                    .font(.firaCode(12))
                    .foregroundColor(.draculaComment)
            }
            .foregroundColor(.draculaPurple)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.draculaPurple.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.draculaPurple.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat card

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.firaCodeSemiBold(28))
                .foregroundColor(.draculaPurple)
            Text(label)
                .font(.firaCode(11))
                .foregroundColor(.draculaComment)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.draculaCurrentLine)
        )
    }
}

// MARK: - Active agent card

private struct ActiveAgentCard: View {
    @ObservedObject var session: SSHSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Session name
            Text(session.profile.nickname)
                .font(.firaCodeMedium(14))
                .foregroundColor(.draculaFg)

            // Agent type + status with icon
            if let agent = session.activeAgent {
                HStack(spacing: 6) {
                    Image(systemName: session.agentStatus.sfSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(session.agentStatus.draculaColor)
                    Text(agent.displayName)
                        .font(.firaCode(11))
                        .foregroundColor(session.agentStatus.draculaColor)
                    Text("·")
                        .foregroundColor(.draculaComment)
                    Text(session.agentStatus.displayName)
                        .font(.firaCode(11))
                        .foregroundColor(session.agentStatus.draculaColor)
                }
            }

            // Last activity message
            if let activity = session.lastActivityMessage {
                Text(activity)
                    .font(.firaCode(10))
                    .foregroundColor(.draculaComment)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.draculaCurrentLine)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(session.agentStatus.draculaColor.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

// MARK: - SessionTerminalView

/// Observes the session so it re-renders when connectionStatus changes.
private struct SessionTerminalView: View {
    @ObservedObject var session: SSHSession
    @EnvironmentObject var appState: AppState
    let isSelected: Bool

    var body: some View {
        if session.profile.isLocal {
            LocalTerminalView(session: session, fontSize: appState.terminalFontSize, isSelected: isSelected)
        } else {
            switch session.connectionStatus {
            case .connected:
                SSHTerminalView(session: session, fontSize: appState.terminalFontSize, isSelected: isSelected)
            case .disconnected, .error:
                DisconnectedPlaceholder(session: session)
            case .connecting:
                ZStack {
                    DraculaVibrancyBackground(cardStyle: true)
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.draculaPurple)
                        Text("Connecting…")
                            .font(Font.firaCode(13))
                            .foregroundColor(Color.draculaFg)
                    }
                }
            }
        }
    }
}

// MARK: - DisconnectedPlaceholder

private struct DisconnectedPlaceholder: View {
    @ObservedObject var session: SSHSession
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            DraculaVibrancyBackground(cardStyle: true)

            VStack(spacing: 16) {
                Image(systemName: "network.slash")
                    .font(.system(size: 40))
                    .foregroundColor(.draculaComment)

                Text(session.profile.nickname)
                    .font(.firaCodeMedium(16))
                    .foregroundColor(.draculaFg)

                if case .error(let msg) = session.connectionStatus {
                    Text(msg)
                        .font(.firaCode(12))
                        .foregroundColor(.draculaRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button("Connect") {
                    appState.connect(session: session)
                }
                .font(.firaCodeMedium(13))
                .foregroundColor(.draculaBg)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.draculaPurple)
                )
                .buttonStyle(.plain)
            }
        }
    }
}
