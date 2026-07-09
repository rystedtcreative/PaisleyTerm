import Foundation

/// Pure text-analysis helpers for interpreting agent terminal output.
///
/// Hoisted out of `AgentMonitor` (which stays in the macOS app as the
/// `@MainActor` orchestrator) so the regression-prone parsing logic can be
/// unit-tested on any platform. Every function here is pure — no session or
/// UI state — and the behavior is identical to the original `AgentMonitor`
/// implementations.
public enum AgentOutputAnalysis {

    // Bare status words that duplicate line 2 — skip them as thinking context.
    static let redundantThinkingWords: Set<String> = [
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

    public static func stripANSI(_ text: String) -> String {
        guard let re = ansiRegex else { return text }
        return re.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }

    public static func stripCSIRemnants(_ text: String) -> String {
        guard let re = csiRemnantRegex else { return text }
        return re.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }

    // MARK: - Alternate screen (TUI) lifecycle detection

    public static func containsAlternateScreenEnter(_ s: String) -> Bool {
        s.contains("\u{1B}[?1049h")
            || s.contains("\u{1B}[?1047h")
            || s.contains("\u{1B}[?47h")
    }

    public static func containsAlternateScreenExit(_ s: String) -> Bool {
        s.contains("\u{1B}[?1049l")
            || s.contains("\u{1B}[?1047l")
            || s.contains("\u{1B}[?47l")
    }

    // MARK: - Activity message extraction

    /// Extracts a short, human-readable activity line from a chunk of agent output.
    /// Returns the first matching line, trimmed to 60 characters, or nil if nothing found.
    public static func extractActivityMessage(from text: String, agent: AgentType) -> String? {
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
            if let match = lines.first(where: { line in
                line.contains("Bash(") || line.contains("Edit(") || line.contains("Read(")
                    || line.contains("Write(") || line.contains("Grep(") || line.contains("Glob(")
                    || line.contains("Webfetch(") || line.contains("WebFetch(")
                    || line.contains("Tool:") || line.contains("Running:")
            }) {
                let trimmed = match.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : String(trimmed.prefix(60))
            }
        }
        return nil
    }

    /// Extracts context text from a thinking-state output chunk.
    /// Returns the first substantive line after cleaning, or nil.
    public static func extractThinkingMessage(from text: String, agent: AgentType) -> String? {
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
            var candidate = stripCSIRemnants(printable).trimmingCharacters(in: .whitespaces)

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
            let isRedundant = redundantThinkingWords.contains(where: { word in
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

    // MARK: - Launch failure detection

    public static func detectLaunchFailure(in text: String, for agent: AgentType) -> String? {
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
