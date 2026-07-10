import Foundation

// MARK: - Protocol

public protocol AgentOutputParser {
    func parse(_ output: String) -> AgentStatus?
}

// MARK: - Claude Code

public struct ClaudeCodeParser: AgentOutputParser {
    // Claude Code's actual spinner frames: ·✢✳✶✽ (U+00B7, U+2722, U+2733, U+2736, U+273D)
    // NOT the braille set ⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏ — those are a different tool.
    private static let spinnerSet: Set<Unicode.Scalar> = Set(
        "·✢✳✶✽".unicodeScalars
    )

    public init() {}

    public func parse(_ output: String) -> AgentStatus? {
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

public struct OpenCodeParser: AgentOutputParser {
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

    public init() {}

    public func parse(_ output: String) -> AgentStatus? {
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
