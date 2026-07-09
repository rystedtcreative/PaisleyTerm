import XCTest
@testable import PaisleyCore

// Characterization tests: these lock down the CURRENT behavior of the agent
// output parsers as extracted from AgentMonitor.swift. They exist to catch
// regressions during the Linux refactor — if a change alters a verdict here,
// that is a behavior change and must be intentional.

final class ClaudeCodeParserTests: XCTestCase {
    private let parser = ClaudeCodeParser()

    func testPermissionPromptsAreWaiting() {
        XCTAssertEqual(parser.parse("Do you want to proceed?"), .waiting)
        XCTAssertEqual(parser.parse("Continue? [y/N]"), .waiting)
        XCTAssertEqual(parser.parse("Continue? [Y/n]"), .waiting)
        XCTAssertEqual(parser.parse("Claude wants to read config.json"), .waiting)
        XCTAssertEqual(parser.parse("Yes, during this session"), .waiting)
        XCTAssertEqual(parser.parse("No, and tell Claude what to do differently"), .waiting)
    }

    func testToolInvocationsAreExecuting() {
        XCTAssertEqual(parser.parse("⏺ Bash(ls -la)"), .executing)
        XCTAssertEqual(parser.parse("Read(/etc/hosts)"), .executing)
        XCTAssertEqual(parser.parse("Running: make build"), .executing)
        XCTAssertEqual(parser.parse("TodoWrite(...)"), .executing)
        XCTAssertEqual(parser.parse("WebSearch(query)"), .executing)
    }

    func testSpinnerFramesAreThinking() {
        XCTAssertEqual(parser.parse("·"), .thinking)
        XCTAssertEqual(parser.parse("✳ crunching"), .thinking)
        XCTAssertEqual(parser.parse("✽"), .thinking)
    }

    func testBrailleIsNotAClaudeSpinner() {
        // Braille belongs to OpenCode; for Claude it must not read as thinking.
        XCTAssertNil(parser.parse("⠋"))
    }

    func testErrorLineIsCaptured() {
        XCTAssertEqual(parser.parse("  Error: something broke  "), .error("Error: something broke"))
        XCTAssertEqual(parser.parse("✗ compilation failed"), .error("✗ compilation failed"))
    }

    func testPlainOutputIsNil() {
        XCTAssertNil(parser.parse("total 48"))
        XCTAssertNil(parser.parse("the quick brown fox"))
    }

    func testPriorityWaitingBeatsExecuting() {
        // A chunk with both a prompt and a tool token must report waiting.
        XCTAssertEqual(parser.parse("⏺ Bash(rm)\nDo you want to proceed?"), .waiting)
    }

    func testPriorityExecutingBeatsThinking() {
        // Executing is checked before the spinner branch.
        XCTAssertEqual(parser.parse("✳ ⏺ Bash(x)"), .executing)
    }
}

final class OpenCodeParserTests: XCTestCase {
    private let parser = OpenCodeParser()

    func testPermissionPromptsAreWaiting() {
        XCTAssertEqual(parser.parse("Allow this action?"), .waiting)
        XCTAssertEqual(parser.parse("Always allow"), .waiting)
        XCTAssertEqual(parser.parse("Deny"), .waiting)
        XCTAssertEqual(parser.parse("proceed?"), .waiting)
    }

    func testBrailleSpinnerIsThinking() {
        XCTAssertEqual(parser.parse("⠋ working"), .thinking)
        XCTAssertEqual(parser.parse("⣾"), .thinking)
    }

    func testThinkingLabelsAreCaseInsensitive() {
        XCTAssertEqual(parser.parse("Thinking about the problem"), .thinking)
        XCTAssertEqual(parser.parse("GENERATING output"), .thinking)
        XCTAssertEqual(parser.parse("press esc to interrupt"), .thinking)
    }

    func testToolTokensAreExecuting() {
        XCTAssertEqual(parser.parse("Bash(npm test)"), .executing)
        XCTAssertEqual(parser.parse("Edit(main.go)"), .executing)
    }

    func testBoxDrawingChromeIsNotASignal() {
        // Regression guard: OpenCode redraws "╭─" every frame; it must NOT be a
        // state signal (this bug once masked the thinking status entirely).
        XCTAssertNil(parser.parse("╭─────────────╮"))
        XCTAssertNil(parser.parse("│ regular panel text │"))
    }

    func testPriorityThinkingBeatsExecuting() {
        // A reasoning frame that also contains a tool token reports thinking.
        XCTAssertEqual(parser.parse("⠙ Bash(x)"), .thinking)
    }

    func testFailureLineIsError() {
        XCTAssertEqual(parser.parse("build failed with 2 errors"), .error("build failed with 2 errors"))
    }

    func testPlainOutputIsNil() {
        XCTAssertNil(parser.parse("regular output line"))
    }
}
