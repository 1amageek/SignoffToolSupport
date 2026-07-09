import Foundation
import Synchronization

final class TimedProcessCompletionBox: Sendable {
    private struct State: Sendable {
        var stdoutClosed = false
        var stderrClosed = false
        var processTerminated = false
        var processGroupCleanupComplete = false
        var exitCode: Int32 = 0
        var didCancel = false
        var didTimeout = false
        var cancellationCheckFailure: String?
        var didResume = false
        var forceFinalizeScheduled = false

        var pipesClosed: Bool {
            stdoutClosed && stderrClosed
        }

        var isComplete: Bool {
            pipesClosed && processTerminated && processGroupCleanupComplete
        }

        var snapshot: TimedProcessCompletionSnapshot {
            TimedProcessCompletionSnapshot(
                exitCode: exitCode,
                didCancel: didCancel,
                didTimeout: didTimeout,
                cancellationCheckFailure: cancellationCheckFailure
            )
        }
    }

    private let storage = Mutex(State())

    var pipesClosed: Bool {
        storage.withLock { $0.pipesClosed }
    }

    var shouldStopMonitoring: Bool {
        storage.withLock { $0.didResume || $0.processTerminated }
    }

    func markStdoutClosed() {
        storage.withLock { $0.stdoutClosed = true }
    }

    func markStderrClosed() {
        storage.withLock { $0.stderrClosed = true }
    }

    func markProcessTerminated(exitCode: Int32) {
        storage.withLock {
            $0.processTerminated = true
            $0.exitCode = exitCode
        }
    }

    func markProcessGroupCleanupComplete() {
        storage.withLock { $0.processGroupCleanupComplete = true }
    }

    func markCancelled() {
        storage.withLock { $0.didCancel = true }
    }

    func markTimedOut() {
        storage.withLock { $0.didTimeout = true }
    }

    func markCancellationCheckFailed(_ message: String) {
        storage.withLock { $0.cancellationCheckFailure = message }
    }

    func markResumedIfNeeded() -> Bool {
        storage.withLock { completion -> Bool in
            guard !completion.didResume else { return false }
            completion.didResume = true
            return true
        }
    }

    func markForcedFinalizeScheduledIfNeeded() -> Bool {
        storage.withLock { completion -> Bool in
            guard !completion.didResume, !completion.forceFinalizeScheduled else { return false }
            completion.forceFinalizeScheduled = true
            return true
        }
    }

    func snapshotIfReady(force: Bool) -> TimedProcessCompletionSnapshot? {
        storage.withLock { completion -> TimedProcessCompletionSnapshot? in
            guard !completion.didResume else { return nil }
            guard force || completion.isComplete else { return nil }
            completion.didResume = true
            return completion.snapshot
        }
    }
}

struct TimedProcessCompletionSnapshot: Sendable {
    let exitCode: Int32
    let didCancel: Bool
    let didTimeout: Bool
    let cancellationCheckFailure: String?
}
