import SwiftUI
import PaisleyCore

struct SessionRowView: View {
    @ObservedObject var session: SSHSession
    var isSelected: Bool = false

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            statusDot
            sessionInfo
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status dot

    private var statusDot: some View {
        let isActive = session.agentStatus == .thinking || session.agentStatus == .executing
        return ZStack {
            Circle()
                .stroke(currentStatusColor.opacity(0.35), lineWidth: 3)
                .frame(width: 16, height: 16)
                .scaleEffect(isActive && pulse ? 1.4 : 1.0)
                .opacity(isActive ? 1.0 : 0.0)

            Circle()
                .fill(currentStatusColor)
                .frame(width: 8, height: 8)

            if session.activeAgent != nil && session.agentStatus != .inactive {
                Image(systemName: "sparkle")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundColor(Color.draculaBg)
            }
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Text block

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.profile.nickname)
                .font(Font.firaCodeMedium(13))
                .foregroundColor(Color.draculaFg)
                .lineLimit(1)

            if let agent = session.activeAgent {
                HStack(spacing: 4) {
                    Image(systemName: session.agentStatus.sfSymbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(currentStatusColor)
                    Text(agent.displayName)
                        .font(Font.firaCode(10))
                        .foregroundColor(currentStatusColor)
                }

                Text(session.agentStatus.displayName.uppercased())
                    .font(Font.firaCode(10))
                    .fontWeight(.semibold)
                    .tracking(0.5)
                    .foregroundColor(currentStatusColor)
            } else {
                Text(session.connectionStatus.displayName)
                    .font(Font.firaCode(11))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Color resolution

    private var currentStatusColor: Color {
        session.activeAgent != nil
            ? session.agentStatus.draculaColor
            : session.connectionStatus.draculaColor
    }

    // draculaComment is low-contrast against the draculaCurrentLine selection bg,
    // so when the row is selected we lift secondary text closer to full foreground.
    private var secondaryTextColor: Color {
        isSelected ? Color.draculaFg.opacity(0.65) : Color.draculaComment
    }
}
