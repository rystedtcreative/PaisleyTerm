import Foundation
import Combine
import os

// MARK: - Protocol

protocol AgentOutputParser {
    func parse(_ output: String) -> AgentStatus?
}

// MARK: - Claude Code

struct ClaudeCodeParser: AgentOutputParser {
    // Claude Code's actual spinner frames: ·✢✳✶✽ (U+00B7, U+2722, U+2733, U+2736, U+273D)
    // NOT the braille set ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏ — those are a different tool.
    private static let spinnerSet: Set<Unicode.Scalar> = Set(
        "·✢✳✶✽".unicodeScalars
    )

    func parse(_ output: String) -> AgentStatus? {
        // Permission / confirmation prompts (current numbered-list format)
        if output.contains("Yes, during this session")
            || output.contains("Claude wants to")
            || output.contains("No, and tell Claude")
            || output.contains("Do you want to proceed?")
            || output.contains("[y/N]")
            || output.contains("[Y/n]") {
            return .waiting
        }
        // Tool execution: ⏺ (U+23FA) precedes every tool invocation line
        if output.contains("⏺")
            || output.contains("Tool:")
            || output.contains("Running:")
            || output.contains("Bash(")
            || output.contains("Write(")
            || output.contains("Read(")
            || output.contains("Edit(")
            || output.contains("Glob(")
            || output.contains("Grep(")
            || output.contains("WebFetch(")
            || output.contains("WebSearch(")
            || output.contains("Agent(")
            || output.contains("TodoWrite(") {
            return .executing
        }
        if output.unicodeScalars.contains(where: { Self.spinnerSet.contains($0) }) {
            return .thinking
        }
        if let errorLine = output.components(separatedBy: "\n")
            .first(where: { $0.contains("Error:") || $0.contains("error:") || $0.contains("✗ ") }) {
            return .error(errorLine.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

// MARK: - OpenCode

struct OpenCodeParser: AgentOutputParser {
    // TODO: calibrate against live opencode output.
    //
    // Calibration notes (root cause of the missing "thinking" status):
    //   * OpenCode is a full-screen TUI (Go / Bubble Tea / Charm). It redraws its
    //     bordered panel every frame, so the box-drawing corner "╭─" appears in
    //     nearly every output chunk. Treating "╭─" as an *executing* signal made
    //     parse() return .executing on almost every frame, so the thinking branch
    //     below was never reached. Box-drawing chrome is therefore NOT a state
    //     signal anymore — only real tool-call tokens are.
    //   * Spinner frames are detected via a Unicode.Scalar Set (like ClaudeCode)
    //     rather than a regex over the whole chunk. This is robust to chunk
    //     boundaries: any single spinner glyph in a frame is enough to detect
    //     thinking. The full Braille Patterns block (U+2800–U+28FF) is included
    //     because Charm's default spinner is braille and braille virtually never
    //     appears in ordinary terminal output; common circle/dot/arrow spinner
    //     glyphs are included too in case the theme overrides the default.
    //   * Thinking labels are matched case-insensitively.
    private static let spinnerSet: Set<Unicode.Scalar> = {
        var set = Set<Unicode.Scalar>()
        // Full Braille Patterns block — Charm/Bubble Tea default spinner.
        for code in 0x2800...0x28FF {
            if let scalar = Unicode.Scalar(code) { set.insert(scalar) }
        }
        // Common alternative spinner glyphs (circles, dots, arrows, half-blocks).
        let extras = "◐◓◑◒◜◝◞◟◠◡●○◍◌⣾⣽⣻⢿⡿⣟⣯⣷←↖↑↗→↘↓↙▖▘▝▗▌▐▀▄"
        set.formUnion(extras.unicodeScalars)
        return set
    }()

    // Case-insensitive thinking labels emitted by OpenCode's status line / hints.
    private static let thinkingLabels = [
        "thinking", "working", "generating", "reasoning",
        "esc to interrupt", "to interrupt", "interrupt",
    ]

    func parse(_ output: String) -> AgentStatus? {
        let lower = output.lowercased()

        // Waiting: permission/confirmation prompts (highest priority).
        if output.contains("Allow")
            || output.contains("Always allow")
            || output.contains("Deny")
            || output.contains("proceed?")
            || output.contains("[y/N]")
            || output.contains("[Y/n]") {
            return .waiting
        }
        // Thinking: spinner glyph or a thinking label. Checked before the generic
        // executing branch so a reasoning frame is not misread as a tool call.
        // NOTE: box-drawing chrome ("╭─") is deliberately NOT treated as a signal.
        if output.unicodeScalars.contains(where: { Self.spinnerSet.contains($0) })
            || Self.thinkingLabels.contains(where: { lower.contains($0) }) {
            return .thinking
        }
        // Executing: real tool-call tokens only (no UI chrome).
        if output.contains("Bash(")
            || output.contains("Edit(")
            || output.contains("Read(")
            || output.contains("Write(")
            || output.contains("Grep(")
            || output.contains("Glob(")
            || output.contains("Webfetch(")
            || output.contains("WebFetch(")
            || output.contains("Tool:")
            || output.contains("Running:") {
            return .executing
        }
        // Error: Error, ✗, failed
        if let errorLine = output.components(separatedBy: "\n")
            .first(where: { $0.contains("Error") || $0.contains("✗") || $0.contains("failed") }) {
            return .error(errorLine.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

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

    // Bare status words that duplicate line 2 — skip them as thinking context.
    private static let redundantThinkingWords: Set<String> = [
        "thinking", "working", "generating", "reasoning", "processing",
        "analyzing", "loading", "running", "esc to interrupt", "to interrupt", "interrupt",
    ]

    // Strips ANSI/VT escape sequences including OSC sequences so pattern matching sees plain text.
    private static let ansiRegex = try? NSRegularExpression(
        pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#
    )

    // Strips orphaned CSI bracket sequences left behind when an ESC char was split across
    // a chunk boundary and removed by the non-printable filter (e.g. "[32m", "[0m").
    private static let csiRemnantRegex = try? NSRegularExpression(
        pattern: #"\[[0-?]*[ -/]*[@-~]"#
    )

    private static func stripCSIRemnants(_ text: String) -> String {
        guard let re = csiRemnantRegex else { return text }
        return re.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }

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

    private static func stripANSI(_ text: String) -> String {
        guard let re = ansiRegex else { return text }
        return re.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
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
        let didEnter = containsAlternateScreenEnter(combined)
        let didExit = containsAlternateScreenExit(combined)

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

    private func containsAlternateScreenEnter(_ s: String) -> Bool {
        s.contains("\u{1B}[?1049h")
            || s.contains("\u{1B}[?1047h")
            || s.contains("\u{1B}[?47h")
    }

    private func containsAlternateScreenExit(_ s: String) -> Bool {
        s.contains("\u{1B}[?1049l")
            || s.contains("\u{1B}[?1047l")
            || s.contains("\u{1B}[?47l")
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

    // MARK: - Activity message extraction

    /// Extracts a short, human-readable activity line from a chunk of agent output.
    /// Returns the first matching line, trimmed to 60 characters, or nil if nothing found.
    private func extractActivityMessage(from text: String, agent: AgentType) -> String? {
        let lines = text.components(separatedBy: "\n")
        switch agent {
        case .claudeCode:
            // Claude Code prefixes tool calls with ⏺ or uses named patterns like Bash(, Write(, etc.
            let toolPatterns = ["⏺", "Bash(", "Write(", "Read(", "Edit(", "Glob(", "Grep(",
                                "WebFetch(", "WebSearch(", "Agent(", "TodoWrite(", "Running:"]
            if let match = lines.first(where: { line in
                toolPatterns.contains(where: { line.contains($0) })
            }) {
                let trimmed = match.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
            }
        case .openCode:
            // OpenCode tool calls
            if let match = lines.first(where: { $0.contains("Bash(") || $0.contains("Edit(") || $0.contains("Read(") || $0.contains("Write(") || $0.contains("Grep(") || $0.contains("Glob(") || $0.contains("Webfetch(") || $0.contains("WebFetch(") || $0.contains("Tool:") || $0.contains("Running:") }) {
                let trimmed = match.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
            }
        }
        return nil
    }

    /// Extracts context text from a thinking-state output chunk.
    /// Returns the first substantive line after cleaning, or nil.
    private func extractThinkingMessage(from text: String, agent: AgentType) -> String? {
        let claudeSpinners: Set<Character> = Set("·✢✳✶✽")
        let opencodeSpinners: Set<Character> = Set("·✢✳✶✽◐◓◑◒◜◝◞◟◠◡●○")
        let spinners: Set<Character> = agent == .claudeCode ? claudeSpinners : opencodeSpinners
        let brailleRange: ClosedRange<UInt32> = 0x2800...0x28FF

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            // Only match lines where the FIRST visible character is a spinner.
            // This prevents UI chrome like "Baked for 5s · ↑↓" and "? for shortcuts · ←"
            // from matching — they contain · as a separator, not as a leading spinner.
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, let firstScalar = trimmedLine.unicodeScalars.first else { continue }
            let firstIsSpinner = spinners.contains(Character(String(firstScalar)))
            let firstIsBraille = agent == .openCode && brailleRange.contains(firstScalar.value)
            guard firstIsSpinner || firstIsBraille else { continue }

            // Strip leading spinner chars and whitespace.
            var stripped = String(trimmedLine.drop(while: { spinners.contains($0) || $0.isWhitespace }))
            // Remove remaining braille scalars for OpenCode.
            if agent == .openCode {
                stripped = String(String.UnicodeScalarView(stripped.unicodeScalars.filter {
                    !brailleRange.contains($0.value)
                }))
            }

            // Strip non-printable chars (ESC, CR, BEL, BS, DEL) and invisible Unicode
            // (zero-width space U+200B–U+200F, BOM U+FEFF) that survive ANSI stripping.
            let printable = stripped.filter {
                $0.unicodeScalars.allSatisfy { s in
                    s.value >= 32 && s.value != 127
                    && !(s.value >= 0x200B && s.value <= 0x200F)
                    && s.value != 0xFEFF
                }
            }
            // Strip orphaned CSI bracket sequences (e.g. "[32m") whose ESC was removed above.
            var candidate = Self.stripCSIRemnants(printable).trimmingCharacters(in: .whitespaces)

            // Strip any remaining leading non-letter/non-digit chars (stray punctuation,
            // partial escape remnants not caught by the CSI regex, etc.).
            candidate = String(candidate.drop(while: { !$0.isLetter && !$0.isNumber }))
                .trimmingCharacters(in: .whitespaces)

            // Skip timing/cost indicators whose first word starts with a digit or "$"
            // (e.g. "5s · Cost: $0.003", "1.2k tokens").
            let firstWord = candidate.components(separatedBy: " ").first ?? ""
            guard firstWord.first?.isNumber != true && !firstWord.hasPrefix("$") else { continue }

            // Skip redundant status words (exact or with trivial trailing punctuation like "…").
            // Keep if there are letters after the status word — "thinking about X" is useful.
            let normalized = candidate.lowercased()
            let isRedundant = Self.redundantThinkingWords.contains(where: { word in
                guard normalized.hasPrefix(word) else { return false }
                return !normalized.dropFirst(word.count).contains(where: { $0.isLetter })
            })
            guard !isRedundant else { continue }

            if candidate.count >= 8 {
                return String(candidate.prefix(60))
            }
        }
        return nil
    }

    private func process(data: Data) {
        guard let raw = String(data: data, encoding: .utf8) else { return }

        // Scan raw terminal output for alternate-screen (TUI) enter/exit before stripping.
        processTerminalModeChanges(in: raw)

        let text = Self.stripANSI(raw)

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
        if detectLaunchFailure(in: text, for: agent) != nil {
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
                if let msg = extractActivityMessage(from: text, agent: agent) {
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

    private func detectLaunchFailure(in text: String, for agent: AgentType) -> String? {
        let cmd = agent.rawValue.lowercased()

        for line in text.components(separatedBy: "\n") {
            let lower = line.lowercased()
            guard lower.contains(cmd) else { continue }

            if lower.contains("command not found")
                || lower.contains("no such file or directory")
                || lower.contains("permission denied") {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }
}
