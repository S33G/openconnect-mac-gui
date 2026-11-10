import XCTest
@testable import BetterConnectCore

final class ProcessTests: XCTestCase, @unchecked Sendable {
    func testCancelStopsActiveProcessAndInvalidatesQueuedCommands() async throws {
        let runner = ProcessRunner()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let first = Task { await runner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 15) }
        try await Task.sleep(for: .milliseconds(100))
        let queued = Task { await runner.run(executable: "/usr/bin/touch", arguments: [file.path], timeout: 2) }
        try await Task.sleep(for: .milliseconds(100))
        runner.cancel()
        let result = await first.value
        _ = await queued.value
        XCTAssertNotNil(result.failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testProcessReceivesEOFAndPreservesLiteralArguments() async {
        let runner = ProcessRunner()
        let result = await runner.run(executable: "/bin/cat", arguments: [], timeout: 1)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertNil(result.failure)
        let literal = await runner.run(executable: "/usr/bin/printf", arguments: ["%s", "$(whoami); secret"], timeout: 1)
        XCTAssertEqual(literal.output, "$(whoami); secret")
    }

    func testTimeoutTerminatesOnlyOwnedChild() async {
        let runner = ProcessRunner()
        let start = Date()
        let result = await runner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.05)
        XCTAssertEqual(result.failure, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testOutputIsDrainedButMemoryIsBounded() async {
        let runner = ProcessRunner(outputLimit: 1024)
        let result = await runner.run(executable: "/usr/bin/yes", arguments: ["fixture"], timeout: 1)
        XCTAssertEqual(result.failure, .outputLimit)
        XCTAssertLessThanOrEqual(result.output.utf8.count, 1024)
    }

    func testMissingExecutableReturnsSafeError() async {
        let result = await ProcessRunner().run(executable: "/does/not/exist", arguments: [], timeout: 1)
        XCTAssertEqual(result.failure, .unavailable)
        XCTAssertEqual(result.output, "")
    }
}
