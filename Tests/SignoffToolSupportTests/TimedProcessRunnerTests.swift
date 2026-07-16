import Foundation
import Testing
import SignoffToolSupport
import Synchronization

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

@Suite("Timed process runner")
struct TimedProcessRunnerTests {
    @Test(.timeLimit(.minutes(1)))
    func executableConveniencePreservesArgumentsEnvironmentAndWorkingDirectory() async throws {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appending(path: "TimedProcessRunnerConvenience-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        defer {
            do {
                try FileManager.default.removeItem(at: workingDirectory)
            } catch {
                Issue.record("Failed to remove process-runner fixture: \(error)")
            }
        }

        let result = try await TimedProcessRunner(timeoutSeconds: 5).run(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", "printf '%s\\n' \"$RUNNER_VALUE\"; : > runner-marker"],
            environment: ["RUNNER_VALUE": "canonical-runner"],
            workingDirectory: workingDirectory
        )

        #expect(result.exitCode == 0)
        let lines = result.standardOutput.split(separator: "\n").map(String.init)
        #expect(lines == ["canonical-runner"])
        #expect(
            FileManager.default.fileExists(
                atPath: workingDirectory.appending(path: "runner-marker").path(percentEncoded: false)
            )
        )
        #expect(result.standardError.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationKillsProcessGroupThatIgnoresTerminate() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; (trap '' TERM; while true; do sleep 1; done) & echo child=$!; while true; do sleep 1; done"]

        let task = Task {
            try await TimedProcessRunner(
                timeoutSeconds: 30,
                terminationGraceSeconds: 0.1,
                pipeDrainGraceSeconds: 0.05
            ).run(process: process)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        var didCancel = false
        var childPID: pid_t?
        do {
            _ = try await task.value
        } catch let error as TimedProcessError {
            switch error {
            case .cancelled(_, let standardOutput, _):
                didCancel = true
                childPID = parseChildPID(from: standardOutput)
            default:
                throw error
            }
        } catch {
            throw error
        }

        #expect(didCancel)
        #expect(!process.isRunning)
        let childPIDValue = try #require(childPID)
        await verifyChildProcessCleanup(childPIDValue)
    }

    @Test(.timeLimit(.minutes(1)))
    func externalCancellationCheckKillsProcessGroupThatIgnoresTerminate() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; (trap '' TERM; while true; do sleep 1; done) & echo child=$!; while true; do sleep 1; done"]

        let cancellation = CancellationProbe()
        let task = Task {
            try await TimedProcessRunner(
                timeoutSeconds: 30,
                terminationGraceSeconds: 0.1,
                pipeDrainGraceSeconds: 0.05
            ).run(
                process: process,
                cancellationCheck: {
                    cancellation.isCancelled()
                }
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        cancellation.cancel()

        var didCancel = false
        var childPID: pid_t?
        do {
            _ = try await task.value
        } catch let error as TimedProcessError {
            switch error {
            case .cancelled(_, let standardOutput, _):
                didCancel = true
                childPID = parseChildPID(from: standardOutput)
            default:
                throw error
            }
        } catch {
            throw error
        }

        #expect(didCancel)
        #expect(!process.isRunning)
        let childPIDValue = try #require(childPID)
        await verifyChildProcessCleanup(childPIDValue)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationCheckFailureKillsProcessGroupThatIgnoresTerminate() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; (trap '' TERM; while true; do sleep 1; done) & echo child=$!; while true; do sleep 1; done"]

        let cancellation = ThrowingCancellationProbe()
        let task = Task {
            try await TimedProcessRunner(
                timeoutSeconds: 30,
                terminationGraceSeconds: 0.1,
                pipeDrainGraceSeconds: 0.05
            ).run(
                process: process,
                cancellationCheck: {
                    try cancellation.check()
                }
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        cancellation.fail()

        var didFailCancellationCheck = false
        var childPID: pid_t?
        do {
            _ = try await task.value
        } catch let error as TimedProcessError {
            switch error {
            case .cancellationCheckFailed(_, _, let standardOutput, _):
                didFailCancellationCheck = true
                childPID = parseChildPID(from: standardOutput)
            default:
                throw error
            }
        } catch {
            throw error
        }

        #expect(didFailCancellationCheck)
        #expect(!process.isRunning)
        let childPIDValue = try #require(childPID)
        await verifyChildProcessCleanup(childPIDValue)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutEscalatesToSIGKILLWhenProcessIgnoresTerminate() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", "trap '' TERM; (trap '' TERM; while true; do sleep 1; done) & echo child=$!; while true; do sleep 1; done"]

        var didTimeout = false
        var childPID: pid_t?
        do {
            _ = try await TimedProcessRunner(
                timeoutSeconds: 0.3,
                terminationGraceSeconds: 0.1,
                pipeDrainGraceSeconds: 0.05
            ).run(process: process)
        } catch let error as TimedProcessError {
            switch error {
            case .timedOut(_, _, let standardOutput, _):
                didTimeout = true
                childPID = parseChildPID(from: standardOutput)
            default:
                throw error
            }
        } catch {
            throw error
        }

        #expect(didTimeout)
        #expect(!process.isRunning)
        let childPIDValue = try #require(childPID)
        await verifyChildProcessCleanup(childPIDValue)
    }

    @Test(.timeLimit(.minutes(1)))
    func launchCreatesProcessGroupBeforeDescendantsFork() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c",
            "root=$$; root_pgid=$(ps -o pgid= -p $$ | tr -d ' '); (trap '' TERM; while true; do sleep 1; done) & child=$!; child_pgid=$(ps -o pgid= -p $child | tr -d ' '); echo root=$root; echo root_pgid=$root_pgid; echo child=$child; echo child_pgid=$child_pgid; trap '' TERM; while true; do sleep 1; done",
        ]

        let task = Task {
            try await TimedProcessRunner(
                timeoutSeconds: 30,
                terminationGraceSeconds: 0.1,
                pipeDrainGraceSeconds: 0.05
            ).run(process: process)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        let standardOutput: String
        do {
            _ = try await task.value
            Issue.record("Expected process cancellation")
            return
        } catch let error as TimedProcessError {
            switch error {
            case .cancelled(_, let output, _):
                standardOutput = output
            default:
                throw error
            }
        } catch {
            throw error
        }

        let rootPID = try #require(parsePID(named: "root", from: standardOutput))
        let rootProcessGroupID = try #require(parsePID(named: "root_pgid", from: standardOutput))
        let childPID = try #require(parsePID(named: "child", from: standardOutput))
        let childProcessGroupID = try #require(parsePID(named: "child_pgid", from: standardOutput))
        #expect(rootProcessGroupID == rootPID)
        #expect(childProcessGroupID == rootPID)
        await verifyChildProcessCleanup(childPID)
    }

    @Test func invalidTimeoutConfigurationThrowsBeforeLaunch() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/true")

        var didThrowExpectedError = false
        do {
            _ = try await TimedProcessRunner(timeoutSeconds: .nan).run(process: process)
        } catch let error as TimedProcessError {
            didThrowExpectedError = error == .invalidConfiguration("timeoutSeconds must be positive finite seconds")
        } catch {
            throw error
        }

        #expect(didThrowExpectedError)
        #expect(!process.isRunning)
    }

    @Test func invalidGraceConfigurationThrowsBeforeLaunch() async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/true")

        var didThrowExpectedError = false
        do {
            _ = try await TimedProcessRunner(terminationGraceSeconds: -.infinity).run(process: process)
        } catch let error as TimedProcessError {
            didThrowExpectedError = error == .invalidConfiguration("terminationGraceSeconds must be finite and non-negative")
        } catch {
            throw error
        }

        #expect(didThrowExpectedError)
        #expect(!process.isRunning)
    }

    private func parseChildPID(from standardOutput: String) -> pid_t? {
        parsePID(named: "child", from: standardOutput)
    }

    private func parsePID(named name: String, from standardOutput: String) -> pid_t? {
        let prefix = "\(name)="
        for line in standardOutput.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix(prefix) else { continue }
            return pid_t(String(line.dropFirst(prefix.count)))
        }
        return nil
    }

    private func isProcessAlive(_ pid: pid_t) -> Bool {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
        #else
        return false
        #endif
    }

    private func waitForProcessExit(_ pid: pid_t) async -> Bool {
        for _ in 0..<20 {
            if !isProcessAlive(pid) {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return !isProcessAlive(pid)
            }
        }
        return !isProcessAlive(pid)
    }

    private func verifyChildProcessCleanup(_ pid: pid_t) async {
        guard canInspectProcessTable() else {
            forceKill(pid)
            return
        }
        let childExited = await waitForProcessExit(pid)
        #expect(childExited)
    }

    private func canInspectProcessTable() -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func forceKill(_ pid: pid_t) {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        Darwin.kill(pid, SIGKILL)
        #endif
    }
}

private final class CancellationProbe: Sendable {
    private let state = Mutex(false)

    func cancel() {
        state.withLock { $0 = true }
    }

    func isCancelled() -> Bool {
        state.withLock { $0 }
    }
}

private final class ThrowingCancellationProbe: Sendable {
    private let state = Mutex(false)

    func fail() {
        state.withLock { $0 = true }
    }

    func check() throws -> Bool {
        if state.withLock({ $0 }) {
            throw CancellationProbeError()
        }
        return false
    }
}

private struct CancellationProbeError: Error, Sendable, CustomStringConvertible {
    var description: String {
        "cancellation probe failed"
    }
}
