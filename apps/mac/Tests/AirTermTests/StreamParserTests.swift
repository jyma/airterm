import XCTest
@testable import AirTerm

final class StreamParserTests: XCTestCase {

    func testParsePlainText() {
        var events: [TerminalEvent] = []
        let parser = StreamParser { events.append($0) }

        parser.feed("Hello world\n")

        XCTAssertEqual(events.count, 1)
        if case .message(let text) = events[0] {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected message event")
        }
    }

    func testParseJSONMessage() {
        var events: [TerminalEvent] = []
        let parser = StreamParser { events.append($0) }

        parser.feed("{\"type\": \"message\", \"text\": \"Found 3 issues\"}\n")

        XCTAssertEqual(events.count, 1)
        if case .message(let text) = events[0] {
            XCTAssertEqual(text, "Found 3 issues")
        } else {
            XCTFail("Expected message event")
        }
    }

    func testParseApproval() {
        var events: [TerminalEvent] = []
        let parser = StreamParser { events.append($0) }

        let json = "{\"type\": \"approval\", \"tool\": \"Bash\", \"command\": \"npm test\", \"prompt\": \"Allow Bash: npm test?\"}\n"
        parser.feed(json)

        XCTAssertEqual(events.count, 1)
        if case .approval(let tool, let command, let prompt) = events[0] {
            XCTAssertEqual(tool, "Bash")
            XCTAssertEqual(command, "npm test")
            XCTAssertEqual(prompt, "Allow Bash: npm test?")
        } else {
            XCTFail("Expected approval event")
        }
    }

    func testParseToolCall() {
        var events: [TerminalEvent] = []
        let parser = StreamParser { events.append($0) }

        parser.feed("{\"type\": \"tool_use\", \"tool\": \"Read\", \"input\": {}}\n")

        XCTAssertEqual(events.count, 1)
        if case .toolCall(let tool, _, _) = events[0] {
            XCTAssertEqual(tool, "Read")
        } else {
            XCTFail("Expected tool_call event")
        }
    }

    func testParseCompletion() {
        var events: [TerminalEvent] = []
        let parser = StreamParser { events.append($0) }

        parser.feed("{\"type\": \"completion\", \"summary\": \"Task finished\"}\n")

        XCTAssertEqual(events.count, 1)
        if case .completion(let summary) = events[0] {
            XCTAssertEqual(summary, "Task finished")
        } else {
            XCTFail("Expected completion event")
        }
    }

    func testBuffersIncomplete() {
        var events: [TerminalEvent] = []
        let parser = StreamParser { events.append($0) }

        parser.feed("Hello ")
        XCTAssertTrue(events.isEmpty)

        parser.feed("world\n")
        XCTAssertEqual(events.count, 1)
    }

    func testMultipleLines() {
        var events: [TerminalEvent] = []
        let parser = StreamParser { events.append($0) }

        parser.feed("Line 1\nLine 2\nLine 3\n")
        XCTAssertEqual(events.count, 3)
    }
}
