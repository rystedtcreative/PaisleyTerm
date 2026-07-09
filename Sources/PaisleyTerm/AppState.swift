import SwiftUI
import Combine
import PaisleyCore

@MainActor
final class AppState: ObservableObject {
    @Published var sessions: [SSHSession] = []
    @Published var selectedSessionID: UUID?
    @Published var showingAddConnection = false

    @Published var terminalFontSize: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "terminalFontSize")
        return saved > 0 ? CGFloat(saved) : 13.0
    }()

    private static let fontSizeRange: ClosedRange<CGFloat> = 8...32

    func increaseFontSize() {
        terminalFontSize = min(terminalFontSize + 1, Self.fontSizeRange.upperBound)
        UserDefaults.standard.set(Double(terminalFontSize), forKey: "terminalFontSize")
    }

    func decreaseFontSize() {
        terminalFontSize = max(terminalFontSize - 1, Self.fontSizeRange.lowerBound)
        UserDefaults.standard.set(Double(terminalFontSize), forKey: "terminalFontSize")
    }

    func resetFontSize() {
        terminalFontSize = 13
        UserDefaults.standard.set(Double(terminalFontSize), forKey: "terminalFontSize")
    }

    let sshService = SSHService.shared

    private let profileStore = ProfileStore()
    private var monitors: [UUID: AgentMonitor] = [:]

    init() {
        loadProfiles()
    }

    // MARK: - Profile management

    private func loadProfiles() {
        sessions = profileStore.loadProfiles().map { SSHSession(profile: $0) }
        for session in sessions where session.profile.isLocal {
            startMonitor(for: session)
        }
    }

    @discardableResult
    func addProfile(_ profile: ConnectionProfile) -> SSHSession {
        profileStore.addProfile(profile)
        let session = SSHSession(profile: profile)
        sessions.append(session)
        selectedSessionID = session.id
        return session
    }

    func addLocalSession(nickname: String) {
        let session = addProfile(.localProfile(nickname: nickname))
        startMonitor(for: session)
    }

    func removeProfile(id: UUID) {
        stopMonitor(for: id)
        Task { await sshService.disconnect(sessionID: id) }
        sessions.removeAll { $0.id == id }
        profileStore.removeProfile(id: id)
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
    }

    var selectedSession: SSHSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    // MARK: - Connection

    func connect(session: SSHSession) {
        guard !session.profile.isLocal else { return }
        Task {
            do {
                try await sshService.connect(session: session)
                startMonitor(for: session)
            } catch {
                session.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    func disconnect(session: SSHSession) {
        guard !session.profile.isLocal else { return }
        stopMonitor(for: session.id)
        Task { await sshService.disconnect(sessionID: session.id) }
        session.connectionStatus = .disconnected
        session.activeAgent = nil
        session.agentStatus = .inactive
    }

    // MARK: - Agent lifecycle

    func launchAgent(_ agentType: AgentType, in session: SSHSession) {
        // Cancel any pending delayed cleanup from a prior exit so the new agent isn't immediately cleared.
        monitors[session.id]?.cancelPendingExit()
        session.activeAgent = agentType
        session.agentStatus = .idle
        let cmd = Data("\(agentType.rawValue)\n".utf8)
        if session.profile.isLocal {
            session.inputSubject.send(cmd)
        } else {
            sshService.enqueueWrite(cmd, to: session.id)
        }
    }

    func stopAgent(in session: SSHSession) {
        let ctrlC = Data([0x03])
        if session.profile.isLocal {
            session.inputSubject.send(ctrlC)
            session.inputSubject.send(ctrlC)
        } else {
            sshService.enqueueWrite(ctrlC, to: session.id)
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                sshService.enqueueWrite(ctrlC, to: session.id)
            }
        }
    }

    private func send(_ command: String, to session: SSHSession) {
        let data = Data("\(command)\n".utf8)
        if session.profile.isLocal {
            session.inputSubject.send(data)
        } else {
            sshService.enqueueWrite(data, to: session.id)
        }
    }

    func installAgent(_ type: AgentType, in session: SSHSession) {
        send(type.installCommand, to: session)
    }

    func addAgentToPath(_ type: AgentType, in session: SSHSession) {
        let export = type.pathExportLine
        let cmd = "grep -qxF '\(export)' ~/.zshrc || echo '\(export)' >> ~/.zshrc; source ~/.zshrc"
        send(cmd, to: session)
    }

    private func startMonitor(for session: SSHSession) {
        stopMonitor(for: session.id)
        let monitor = AgentMonitor(session: session)
        monitors[session.id] = monitor
        monitor.start()
    }

    private func stopMonitor(for id: UUID) {
        monitors[id]?.stop()
        monitors[id] = nil
    }
}
