import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let output: String
    public let exitCode: Int32
    public let failure: SafeError?
}

/// Serial, bounded subprocess execution. No shell, no stdin, no raw-output logging.
/// Cancellation terminates only the CLI child created by this instance, never Cisco UI/agent.
public final class ProcessRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "betterer-connect.cli", qos: .utility)
    private let lock = NSLock()
    private var active: Process?
    private var generation: UInt64 = 0
    private let outputLimit: Int

    public init(outputLimit: Int = 65_536) { self.outputLimit = outputLimit }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        if let active, active.isRunning { active.terminate() }
    }

    public func run(executable: String, arguments: [String], timeout: TimeInterval,
                    stopAtInteractivePrompt: Bool = false) async -> CommandResult {
        guard !Task.isCancelled else { return CommandResult(output: "", exitCode: -1, failure: .operationCancelled) }
        let ticket = lock.withLock { generation }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: execute(executable, arguments, timeout, stopAtInteractivePrompt, ticket))
            }
        }
    }

    private func execute(_ executable: String, _ arguments: [String], _ timeout: TimeInterval,
                         _ stopAtInteractivePrompt: Bool, _ ticket: UInt64) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "LC_ALL": "C"]
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        lock.lock()
        guard ticket == generation else {
            lock.unlock()
            return CommandResult(output: "", exitCode: -1, failure: .operationCancelled)
        }
        do { try process.run() }
        catch { lock.unlock(); return CommandResult(output: "", exitCode: -1, failure: .unavailable) }
        active = process
        lock.unlock()
        defer {
            lock.lock(); active = nil; lock.unlock()
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }

        let deadline = ProcessInfo.processInfo.systemUptime + max(0.01, timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var failure: SafeError?
        var stopRequestedAt: Double?
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                let remaining = max(0, outputLimit - data.count)
                data.append(contentsOf: buffer.prefix(min(count, remaining)))
                if count > remaining { failure = .outputLimit }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if lock.withLock({ ticket != generation }) { failure = .operationCancelled }
            let interactive = stopAtInteractivePrompt && CiscoParser.needsSSO(String(decoding: data, as: UTF8.self))
            if now >= deadline && failure == nil { failure = .timedOut }
            if (failure != nil || interactive), process.isRunning, stopRequestedAt == nil {
                process.terminate(); stopRequestedAt = now
            }
            if let stopped = stopRequestedAt, now - stopped > 0.25, process.isRunning {
                // Only our still-running child; PID cannot be reused until it exits/reaps.
                kill(process.processIdentifier, SIGKILL)
            }
            if !process.isRunning && count <= 0 { break }
            if count <= 0 { Thread.sleep(forTimeInterval: 0.01) }
        }
        process.waitUntilExit()
        return CommandResult(output: String(decoding: data, as: UTF8.self), exitCode: process.terminationStatus, failure: failure)
    }
}
