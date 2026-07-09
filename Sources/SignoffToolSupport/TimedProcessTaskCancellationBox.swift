import Foundation
import Synchronization

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

final class TimedProcessTaskCancellationBox: Sendable {
    private struct State: Sendable {
        var wasCancelled = false
        var completionBox: TimedProcessCompletionBox?
        var launch: TimedProcessLaunch?
        var killScheduled = false
    }

    private let terminationGraceSeconds: Double
    private let storage = Mutex(State())

    init(terminationGraceSeconds: Double) {
        self.terminationGraceSeconds = terminationGraceSeconds
    }

    var isCancelled: Bool {
        storage.withLock { $0.wasCancelled }
    }

    func register(completionBox: TimedProcessCompletionBox) {
        let shouldMarkCancelled = storage.withLock { state -> Bool in
            state.completionBox = completionBox
            return state.wasCancelled
        }
        if shouldMarkCancelled {
            completionBox.markCancelled()
        }
    }

    func register(launch: TimedProcessLaunch) -> Bool {
        storage.withLock { state -> Bool in
            state.launch = launch
            return state.wasCancelled
        }
    }

    func cancel() {
        let snapshot = storage.withLock { state -> (TimedProcessCompletionBox?, TimedProcessLaunch?, Bool) in
            state.wasCancelled = true
            let shouldScheduleKill = state.launch != nil && !state.killScheduled
            if shouldScheduleKill {
                state.killScheduled = true
            }
            return (state.completionBox, state.launch, shouldScheduleKill)
        }
        snapshot.0?.markCancelled()
        if let launch = snapshot.1 {
            sendTerminationSignal(to: launch, scheduleKill: snapshot.2)
        }
    }

    func terminateLaunchRegisteredAfterCancellation(_ launch: TimedProcessLaunch) {
        let shouldScheduleKill = storage.withLock { state -> Bool in
            guard state.wasCancelled, !state.killScheduled else { return false }
            state.killScheduled = true
            return true
        }
        guard shouldScheduleKill else { return }
        sendTerminationSignal(to: launch, scheduleKill: true)
    }

    private func sendTerminationSignal(to launch: TimedProcessLaunch, scheduleKill: Bool) {
        _ = TimedProcessSpawner.sendSignalToProcessGroup(
            processID: launch.processID,
            processGroupID: launch.processGroupID,
            signal: SIGTERM
        )
        if scheduleKill {
            scheduleForcedKillIfNeeded(launch)
        }
    }

    private func scheduleForcedKillIfNeeded(_ launch: TimedProcessLaunch) {
        let graceSeconds = terminationGraceSeconds
        Task.detached { @Sendable in
            do {
                let boundedSeconds = max(0, graceSeconds)
                let nanoseconds = UInt64((boundedSeconds * 1_000_000_000).rounded())
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard TimedProcessSpawner.isProcessGroupAlive(launch.processGroupID) else { return }
            _ = TimedProcessSpawner.sendSignalToProcessGroup(
                processID: launch.processID,
                processGroupID: launch.processGroupID,
                signal: SIGKILL
            )
        }
    }
}
