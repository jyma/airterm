import XCTest
@testable import AirTerm

final class OutputParserTests: XCTestCase {

    func testParseClaudeMessage() {
        let parser = OutputParser()
        let text = """
        ╭─ Claude
        │ I found 3 security issues in auth.ts
        │ Let me fix them now.
        ╰─
        """
        let events = parser.parseDelta(text)

        let messages = events.compactMap { event -> String? in
            if case .message(let text) = event { return text }
            return nil
        }
        XCTAssertTrue(messages.contains("I found 3 security issues in auth.ts"))
        XCTAssertTrue(messages.contains("Let me fix them now."))
    }

    func testParseToolCall() {
        let parser = OutputParser()
        let events = parser.parseDelta("► Read src/auth.ts (245 lines)\n")

        XCTAssertEqual(events.count, 1)
        if case .toolCall(let tool, _, _) = events[0] {
            XCTAssertEqual(tool, "Read")
        } else {
            XCTFail("Expected tool_call event")
        }
    }

    func testParseToolCallWithColon() {
        let parser = OutputParser()
        let events = parser.parseDelta("► Bash: npm test\n")

        XCTAssertEqual(events.count, 1)
        if case .toolCall(let tool, let args, _) = events[0] {
            XCTAssertEqual(tool, "Bash")
            XCTAssertEqual(args["command"], "npm test")
        } else {
            XCTFail("Expected tool_call event")
        }
    }

    func testParseApproval() {
        let parser = OutputParser()
        let events = parser.parseDelta("Allow Bash: npm test? [y/n]\n")

        XCTAssertEqual(events.count, 1)
        if case .approval(let tool, let command, _) = events[0] {
            XCTAssertEqual(tool, "Bash")
            XCTAssertEqual(command, "npm test")
        } else {
            XCTFail("Expected approval event")
        }
    }

    func testParseCompletion() {
        let parser = OutputParser()
        let events = parser.parseDelta("✓ All tests passed, task complete\n")

        let completions = events.compactMap { event -> String? in
            if case .completion(let summary) = event { return summary }
            return nil
        }
        XCTAssertFalse(completions.isEmpty)
    }

    func testStripAnsiCodes() {
        let parser = OutputParser()
        let events = parser.parseDelta("\u{1B}[32m► Read\u{1B}[0m src/auth.ts\n")

        XCTAssertFalse(events.isEmpty)
        if case .toolCall(let tool, _, _) = events[0] {
            XCTAssertEqual(tool, "Read")
        }
    }

    func testPlainText() {
        let parser = OutputParser()
        let events = parser.parseDelta("Some plain text output\n")

        XCTAssertEqual(events.count, 1)
        if case .message(let text) = events[0] {
            XCTAssertEqual(text, "Some plain text output")
        } else {
            XCTFail("Expected message event")
        }
    }
}
