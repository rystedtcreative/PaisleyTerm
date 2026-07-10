import XCTest
@testable import PaisleyCore

// Characterization tests for the pure text-analysis helpers hoisted out of
// AgentMonitor. These encode current behavior of the trickier extraction /
// cleanup logic so the refactor can't silently change it.

final class AgentOutputAnalysisTests: XCTestCase {

    // MARK: stripANSI

    func testStripANSIRemovesColorCodes() {
        XCTAssertEqual(AgentOutputAnalysis.stripANSI("\u{1B}[32mhello\u{1B}[0m"), "hello")
    }

    func testStripANSILeavesPlainTextUntouched() {
        XCTAssertEqual(AgentOutputAnalysis.stripANSI("no escapes here"), "no escapes here")
    }

    // MARK: alternate-screen detection

    func testAlternateScreenEnter() {
        XCTAssertTrue(AgentOutputAnalysis.containsAlternateScreenEnter("\u{1B}[?1049h"))
        XCTAssertTrue(AgentOutputAnalysis.containsAlternateScreenEnter("prefix\u{1B}[?47hsuffix"))
        XCTAssertFalse(AgentOutputAnalysis.containsAlternateScreenEnter("plain"))
        // An exit sequence is not an enter.
        XCTAssertFalse(AgentOutputAnalysis.containsAlternateScreenEnter("\u{1B}[?1049l"))
    }

    func testAlternateScreenExit() {
        XCTAssertTrue(AgentOutputAnalysis.containsAlternateScreenExit("\u{1B}[?1049l"))
        XCTAssertTrue(AgentOutputAnalysis.containsAlternateScreenExit("\u{1B}[?47l"))
        XCTAssertFalse(AgentOutputAnalysis.containsAlternateScreenExit("plain"))
        XCTAssertFalse(AgentOutputAnalysis.containsAlternateScreenExit("\u{1B}[?1049h"))
    }

    // MARK: extractActivityMessage

    func testActivityMessageClaude() {
        XCTAssertEqual(
            AgentOutputAnalysis.extractActivityMessage(from: "⏺ Bash(ls -la)", agent: .claudeCode),
            "⏺ Bash(ls -la)"
        )
        XCTAssertEqual(
            AgentOutputAnalysis.extractActivityMessage(
                from: "noise\n⏺ Read(/etc/hosts)\nmore noise", agent: .claudeCode),
            "⏺ Read(/etc/hosts)"
        )
    }

    func testActivityMessageOpenCode() {
        XCTAssertEqual(
            AgentOutputAnalysis.extractActivityMessage(from: "Bash(npm test)", agent: .openCode),
            "Bash(npm test)"
        )
    }

    func testActivityMessageNilWhenNoTool() {
        XCTAssertNil(AgentOutputAnalysis.extractActivityMessage(from: "just some text", agent: .claudeCode))
    }

    func testActivityMessageTruncatedTo60() {
        let long = "⏺ Bash(" + String(repeating: "a", count: 100) + ")"
        let result = AgentOutputAnalysis.extractActivityMessage(from: long, agent: .claudeCode)
        XCTAssertEqual(result?.count, 60)
    }

    // MARK: extractThinkingMessage

    func testThinkingMessageClaude() {
        XCTAssertEqual(
            AgentOutputAnalysis.extractThinkingMessage(
                from: "✳ Analyzing the codebase structure", agent: .claudeCode),
            "Analyzing the codebase structure"
        )
    }

    func testThinkingMessageOpenCodeBraille() {
        XCTAssertEqual(
            AgentOutputAnalysis.extractThinkingMessage(
                from: "⠋ Generating response payload", agent: .openCode),
            "Generating response payload"
        )
    }

    func testThinkingMessageSkipsRedundantStatusWord() {
        // A bare status word with nothing after it is not useful context.
        XCTAssertNil(AgentOutputAnalysis.extractThinkingMessage(from: "✳ thinking", agent: .claudeCode))
    }

    func testThinkingMessageSkipsTooShort() {
        XCTAssertNil(AgentOutputAnalysis.extractThinkingMessage(from: "✳ short", agent: .claudeCode))
    }

    func testThinkingMessageIgnoresNonLeadingSpinner() {
        // "·" as a separator (not the first visible char) must not match.
        XCTAssertNil(
            AgentOutputAnalysis.extractThinkingMessage(from: "Baked for 5s · done now", agent: .claudeCode)
        )
    }

    func testThinkingMessageSkipsTimingFirstWord() {
        // First word starting with a digit (timing/cost) is skipped.
        XCTAssertNil(
            AgentOutputAnalysis.extractThinkingMessage(from: "✳ 5s elapsed already now", agent: .claudeCode)
        )
    }

    // MARK: detectLaunchFailure

    func testDetectLaunchFailureClaude() {
        XCTAssertEqual(
            AgentOutputAnalysis.detectLaunchFailure(in: "bash: claude: command not found", for: .claudeCode),
            "bash: claude: command not found"
        )
    }

    func testDetectLaunchFailureOpenCode() {
        XCTAssertEqual(
            AgentOutputAnalysis.detectLaunchFailure(in: "zsh: opencode: command not found", for: .openCode),
            "zsh: opencode: command not found"
        )
    }

    func testDetectLaunchFailureNilWhenRunning() {
        XCTAssertNil(AgentOutputAnalysis.detectLaunchFailure(in: "claude is thinking", for: .claudeCode))
    }

    func testDetectLaunchFailureRequiresCommandAndKeywordOnSameLine() {
        // "claude" and the failure keyword are on different lines → no match.
        XCTAssertNil(
            AgentOutputAnalysis.detectLaunchFailure(
                in: "claude\nsomething: command not found", for: .claudeCode)
        )
    }
}
