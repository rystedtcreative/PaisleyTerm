import Foundation
import Combine
import os
import PaisleyCore

// The agent-output parsers and pure text-analysis helpers live in PaisleyCore
// (platform-agnostic, unit-tested on Linux). AgentMonitor is the macOS-side
// @MainActor orchestrator: it subscribes to a session's output, drives the
// alt-screen lifecycle state machine, and mutates published session state.

// MARK: - Monitor

@MainActor
final class AgentMonitor {
    private var cancellable: AnyCancellable?
    private let session: SSHSession
    private let claudeParser = ClaudeCodeParser()
    private let opencodeParser = OpenCodeParser()
    private var buffer = ""
    private var rawTail = ""
    private var idleTask: Task<Void, Never>?
    private var clearAgentTask: Task<Void, Never>?
    private var isInAlternateScreen = false

    init(session: SSHSession) {
        self.session = session
    }

    func start() {
        // DispatchQueue.main, not RunLoop.main: the RunLoop scheduler only delivers in
        // .default mode, so status parsing (and alt-screen tracking) would stall for the
        // duration of scroll gestures (.eventTracking mode).
        cancellable = session.outputSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.process(data: data)
            }
    }

    func stop() {
        cancellable = nil
        idleTask?.cancel()
        clearAgentTask?.cancel()
        idleTask = nil
        clearAgentTask = nil
        buffer = ""
        rawTail = ""
        isInAlternateScreen = false
    }

    /// Called when an agent is explicitly launched (e.g. via sidebar) to cancel any
    /// pending delayed cleanup from a recent exit, preventing it from clearing the new agent.
    func cancelPendingExit() {
        clearAgentTask?.cancel()
        clearAgentTask = nil
    }

    // After 4 seconds without a new active-state signal, drop back to idle.
    private func scheduleIdleTransition() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            if self.session.agentStatus == .thinking || self.session.agentStatus == .executing {
                self.session.agentStatus = .idle
            }
        }
    }

    // MARK: - Alternate screen (TUI) lifecycle detection

    #if DEBUG
    private static let modeLog = Logger(subsystem: "com.paisley.PaisleyTerm", category: "decset")

    // Logging only — confirms what mouse-tracking modes a live TUI negotiates.
    private func logMouseModeChanges(in raw: String) {
        for mode in ["1000", "1002", "1003", "1006", "1007"] {
            for flag in ["h", "l"] where raw.contains("\u{1B}[?\(mode)\(flag)") {
                Self.modeLog.debug("DECSET ?\(mode, privacy: .public)\(flag, privacy: .public) (\(self.session.profile.nickname, privacy: .public))")
            }
        }
    }
    #endif

    private func processTerminalModeChanges(in raw: String) {
        let combined = rawTail + raw
        let didEnter = AgentOutputAnalysis.containsAlternateScreenEnter(combined)
        let didExit = AgentOutputAnalysis.containsAlternateScreenExit(combined)

        #if DEBUG
        logMouseModeChanges(in: combined)
        #endif

        if didEnter {
            isInAlternateScreen = true
        }

        if didExit {
            isInAlternateScreen = false
            handleAgentExited()
        }

        rawTail = didEnter || didExit ? "" : String(raw.suffix(16))
    }

    private func handleAgentExited() {
        guard session.activeAgent != nil else { return }

        idleTask?.cancel()
        clearAgentTask?.cancel()

        session.agentStatus = .complete
        session.lastActivityMessage = nil

        let exitedAgent = session.activeAgent
        clearAgentTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            guard self.session.activeAgent == exitedAgent else { return }

            self.session.activeAgent = nil
            self.session.agentStatus = .inactive
            self.session.lastActivityMessage = nil
        }
    }

    // MARK: - Output processing

    private func process(data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else { return }

        // Scan raw terminal output for alternate-screen (TUI) enter/exit before stripping.
        processTerminalModeChanges(in: raw)

        let text = AgentOutputAnalysis.stripANSI(raw)

        buffer += text
        if buffer.count > 8_192 {
            buffer = String(buffer.suffix(4_096))
        }

        // Auto-detect agent from output if none is set yet.
        // Use stricter detection to avoid false positives from generic shell words.
        if session.activeAgent == nil {
            if let (agent, status) = detectAgentStart(from: text) {
                clearAgentTask?.cancel()
                clearAgentTask = nil
                session.activeAgent = agent
                session.agentStatus = status
            }
        }

        guard let agent = session.activeAgent else { return }

        // Launch failure detection: if we just launched this agent and the shell says not found,
        // clear the phantom active agent instead of leaving it stuck at idle.
        if AgentOutputAnalysis.detectLaunchFailure(in: text, for: agent) != nil {
            session.agentStatus = .inactive
            session.activeAgent = nil
            session.lastActivityMessage = nil
            return
        }

        let parser: AgentOutputParser = agent == .claudeCode ? claudeParser : opencodeParser
        if let status = parser.parse(text) {
            clearAgentTask?.cancel()
            clearAgentTask = nil
            session.agentStatus = status
            switch status {
            case .executing:
                // Capture the most recent tool-call line for display in the sidebar.
                if let msg = AgentOutputAnalysis.extractActivityMessage(from: text, agent: agent) {
                    session.lastActivityMessage = msg
                }
                scheduleIdleTransition()
            case .thinking:
                // Keep the last executing message visible while thinking — it gives context
                // ("last ran: Read(...)") without trying to parse TUI cursor-positioned output.
                scheduleIdleTransition()
            default:
                // .waiting, .idle, .complete, .error — clear stale context.
                session.lastActivityMessage = nil
            }
        }
    }

    // MARK: - Safer agent start detection

    private func detectAgentStart(from text: String) -> (AgentType, AgentStatus)? {
        let lower = text.lowercased()

        // Manual auto-detection only starts agents in TUI context. Sidebar launches still
        // set activeAgent optimistically, so this path mainly protects manual terminal starts.
        guard isInAlternateScreen else { return nil }

        // Prefer explicit binary names or distinctive Claude markers first.
        let claudeStrong = lower.contains("claude code")
            || text.contains("Claude wants to")
            || text.contains("⏺")
            || text.contains("Do you want to proceed?")
            || text.contains("Bypassing Permissions")

        if claudeStrong {
            return (.claudeCode, claudeParser.parse(text) ?? .idle)
        }

        // For OpenCode, require either the binary name or OpenCode-specific TUI/tool tokens.
        // Do NOT auto-start from generic thinking labels alone ("working", "generating", "interrupt").
        let openCodeStrong = lower.contains("opencode.ai")
            || text.contains("Baked for")
            || text.contains("Bash(")
            || text.contains("Edit(")
            || text.contains("Read(")
            || text.contains("Write(")
            || text.contains("Grep(")
            || text.contains("Glob(")
            || text.contains("Webfetch(")
            || text.contains("WebFetch(")
            || text.contains("Tool:")
            || text.contains("Running:")

        if openCodeStrong {
            return (.openCode, opencodeParser.parse(text) ?? .idle)
        }

        return nil
    }
}
