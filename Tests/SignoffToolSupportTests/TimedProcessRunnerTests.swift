import Foundation
import Testing
import SignoffToolSupport

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

@Suite("Timed process runner")
struct TimedProcessRunnerTests {
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
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(!isProcessAlive(childPIDValue))
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
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(!isProcessAlive(childPIDValue))
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
        for line in standardOutput.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("child=") else { continue }
            return pid_t(String(line.dropFirst("child=".count)))
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
}
