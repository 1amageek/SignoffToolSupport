import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

public struct TimedProcessResult: Sendable, Hashable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public enum TimedProcessError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case launchFailed(executablePath: String, message: String)
    case cancellationCheckFailed(executablePath: String, message: String, standardOutput: String, standardError: String)
    case cancelled(executablePath: String, standardOutput: String, standardError: String)
    case timedOut(executablePath: String, timeoutSeconds: Double, standardOutput: String, standardError: String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid process runner configuration: \(message)"
        case .launchFailed(let executablePath, let message):
            return "Process failed to launch: \(executablePath): \(message)"
        case .cancellationCheckFailed(let executablePath, let message, _, _):
            return "Process cancellation check failed: \(executablePath): \(message)"
        case .cancelled(let executablePath, _, _):
            return "Process was cancelled: \(executablePath)"
        case .timedOut(let executablePath, let timeoutSeconds, _, _):
            return "Process timed out after \(timeoutSeconds)s: \(executablePath)"
        }
    }
}

public struct TimedProcessRunner: Sendable {
    public let timeoutSeconds: Double
    public let terminationGraceSeconds: Double
    public let pipeDrainGraceSeconds: Double

    public init(
        timeoutSeconds: Double = 300,
        terminationGraceSeconds: Double = 2,
        pipeDrainGraceSeconds: Double = 0.25
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.terminationGraceSeconds = terminationGraceSeconds
        self.pipeDrainGraceSeconds = pipeDrainGraceSeconds
    }

    public func run(process: Process) async throws -> TimedProcessResult {
        try await run(process: process, cancellationCheck: nil)
    }

    public func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult {
        let configuration = try makeConfiguration(process: process, cancellationCheck: cancellationCheck)
        try await validateCancellationBeforeLaunch(configuration)

        let cancellationBox = TimedProcessTaskCancellationBox(
            terminationGraceSeconds: configuration.terminationGraceSeconds
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startSession(
                    TimedProcessRunSession(configuration: configuration, continuation: continuation),
                    cancellationBox: cancellationBox
                )
            }
        } onCancel: {
            cancellationBox.cancel()
        }
    }

    private func makeConfiguration(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) throws -> TimedProcessRunConfiguration {
        try validateRunnerConfiguration()
        guard let executableURL = process.executableURL else {
            throw TimedProcessError.launchFailed(
                executablePath: "<unknown>",
                message: "executableURL is required"
            )
        }
        return TimedProcessRunConfiguration(
            executablePath: executableURL.path(percentEncoded: false),
            arguments: process.arguments ?? [],
            environment: process.environment,
            workingDirectory: process.currentDirectoryURL,
            timeoutSeconds: timeoutSeconds,
            terminationGraceSeconds: terminationGraceSeconds,
            pipeDrainGraceSeconds: pipeDrainGraceSeconds,
            cancellationCheck: cancellationCheck
        )
    }

    private func validateRunnerConfiguration() throws {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw TimedProcessError.invalidConfiguration("timeoutSeconds must be positive finite seconds")
        }
        guard terminationGraceSeconds.isFinite, terminationGraceSeconds >= 0 else {
            throw TimedProcessError.invalidConfiguration("terminationGraceSeconds must be finite and non-negative")
        }
        guard pipeDrainGraceSeconds.isFinite, pipeDrainGraceSeconds >= 0 else {
            throw TimedProcessError.invalidConfiguration("pipeDrainGraceSeconds must be finite and non-negative")
        }
    }

    private func validateCancellationBeforeLaunch(_ configuration: TimedProcessRunConfiguration) async throws {
        if Task.isCancelled {
            throw TimedProcessError.cancelled(
                executablePath: configuration.executablePath,
                standardOutput: "",
                standardError: ""
            )
        }
        guard let cancellationCheck = configuration.cancellationCheck else { return }
        do {
            if try await cancellationCheck() {
                throw TimedProcessError.cancelled(
                    executablePath: configuration.executablePath,
                    standardOutput: "",
                    standardError: ""
                )
            }
        } catch let error as TimedProcessError {
            throw error
        } catch {
            throw TimedProcessError.cancellationCheckFailed(
                executablePath: configuration.executablePath,
                message: String(describing: error),
                standardOutput: "",
                standardError: ""
            )
        }
    }

    private func startSession(
        _ session: TimedProcessRunSession,
        cancellationBox: TimedProcessTaskCancellationBox
    ) {
        cancellationBox.register(completionBox: session.state)
        if cancellationBox.isCancelled {
            cancelBeforeLaunch(session)
            return
        }

        let resume = makeResumeHandler(session: session)
        let finalizeIfReady = makeFinalizeHandler(state: session.state, resume: resume)
        let scheduleForcedFinalize = makeForcedFinalizeScheduler(
            state: session.state,
            pipeDrainGraceSeconds: session.configuration.pipeDrainGraceSeconds,
            finalizeIfReady: finalizeIfReady
        )
        installReadabilityHandlers(session: session, finalizeIfReady: finalizeIfReady)
        guard let launch = launchOrFail(session) else { return }
        if cancellationBox.register(launch: launch) {
            session.state.markCancelled()
            cancellationBox.terminateLaunchRegisteredAfterCancellation(launch)
        }
        scheduleExitWaiter(
            launch: launch,
            state: session.state,
            pipeDrainGraceSeconds: session.configuration.pipeDrainGraceSeconds,
            terminationGraceSeconds: session.configuration.terminationGraceSeconds,
            finalizeIfReady: finalizeIfReady,
            scheduleForcedFinalize: scheduleForcedFinalize
        )
        scheduleDeadlineMonitor(
            launch: launch,
            state: session.state,
            timeoutSeconds: session.configuration.timeoutSeconds,
            terminationGraceSeconds: session.configuration.terminationGraceSeconds,
            cancellationCheck: session.configuration.cancellationCheck,
            scheduleForcedFinalize: scheduleForcedFinalize
        )
    }

    private func cancelBeforeLaunch(_ session: TimedProcessRunSession) {
        session.outputPipe.fileHandleForWriting.closeFile()
        session.errorPipe.fileHandleForWriting.closeFile()
        guard session.state.markResumedIfNeeded() else { return }
        session.outputPipe.fileHandleForReading.readabilityHandler = nil
        session.errorPipe.fileHandleForReading.readabilityHandler = nil
        session.outputPipe.fileHandleForReading.closeFile()
        session.errorPipe.fileHandleForReading.closeFile()
        session.continuation.resume(throwing: TimedProcessError.cancelled(
            executablePath: session.configuration.executablePath,
            standardOutput: "",
            standardError: ""
        ))
    }

    private func makeResumeHandler(
        session: TimedProcessRunSession
    ) -> @Sendable (TimedProcessCompletionSnapshot) -> Void {
        { snapshot in
            session.outputPipe.fileHandleForReading.readabilityHandler = nil
            session.errorPipe.fileHandleForReading.readabilityHandler = nil
            let remainingOutput = Self.drainAvailableData(from: session.outputPipe.fileHandleForReading)
            let remainingError = Self.drainAvailableData(from: session.errorPipe.fileHandleForReading)
            if !remainingOutput.isEmpty {
                session.stdoutBuffer.append(remainingOutput)
            }
            if !remainingError.isEmpty {
                session.stderrBuffer.append(remainingError)
            }
            session.outputPipe.fileHandleForReading.closeFile()
            session.errorPipe.fileHandleForReading.closeFile()

            let stdout = Self.utf8String(from: session.stdoutBuffer.snapshot())
            let stderr = Self.utf8String(from: session.stderrBuffer.snapshot())
            if let cancellationCheckFailure = snapshot.cancellationCheckFailure {
                session.continuation.resume(throwing: TimedProcessError.cancellationCheckFailed(
                    executablePath: session.configuration.executablePath,
                    message: cancellationCheckFailure,
                    standardOutput: stdout,
                    standardError: stderr
                ))
                return
            }
            if snapshot.didCancel {
                session.continuation.resume(throwing: TimedProcessError.cancelled(
                    executablePath: session.configuration.executablePath,
                    standardOutput: stdout,
                    standardError: stderr
                ))
                return
            }
            if snapshot.didTimeout {
                session.continuation.resume(throwing: TimedProcessError.timedOut(
                    executablePath: session.configuration.executablePath,
                    timeoutSeconds: session.configuration.timeoutSeconds,
                    standardOutput: stdout,
                    standardError: stderr
                ))
                return
            }
            session.continuation.resume(returning: TimedProcessResult(
                exitCode: snapshot.exitCode,
                standardOutput: stdout,
                standardError: stderr
            ))
        }
    }

    private func makeFinalizeHandler(
        state: TimedProcessCompletionBox,
        resume: @escaping @Sendable (TimedProcessCompletionSnapshot) -> Void
    ) -> @Sendable (_ force: Bool) -> Void {
        { force in
            let snapshot = state.snapshotIfReady(force: force)
            guard let snapshot else { return }
            resume(snapshot)
        }
    }

    private func makeForcedFinalizeScheduler(
        state: TimedProcessCompletionBox,
        pipeDrainGraceSeconds: Double,
        finalizeIfReady: @escaping @Sendable (_ force: Bool) -> Void
    ) -> @Sendable () -> Void {
        {
            guard state.markForcedFinalizeScheduledIfNeeded() else { return }
            Task.detached { @Sendable in
                do {
                    try await Self.sleep(seconds: pipeDrainGraceSeconds)
                } catch {
                    return
                }
                finalizeIfReady(true)
            }
        }
    }

    private func installReadabilityHandlers(
        session: TimedProcessRunSession,
        finalizeIfReady: @escaping @Sendable (_ force: Bool) -> Void
    ) {
        session.outputPipe.fileHandleForReading.readabilityHandler = { handle in
            Self.drainAvailableData(
                from: handle,
                into: session.stdoutBuffer,
                markClosed: session.state.markStdoutClosed,
                finalizeIfReady: finalizeIfReady
            )
        }
        session.errorPipe.fileHandleForReading.readabilityHandler = { handle in
            Self.drainAvailableData(
                from: handle,
                into: session.stderrBuffer,
                markClosed: session.state.markStderrClosed,
                finalizeIfReady: finalizeIfReady
            )
        }
    }

    private func launchOrFail(_ session: TimedProcessRunSession) -> TimedProcessLaunch? {
        do {
            let processID = try TimedProcessSpawner.spawnInNewProcessGroup(
                executablePath: session.configuration.executablePath,
                arguments: session.configuration.arguments,
                environment: session.configuration.environment,
                workingDirectory: session.configuration.workingDirectory,
                outputPipe: session.outputPipe,
                errorPipe: session.errorPipe
            )
            session.outputPipe.fileHandleForWriting.closeFile()
            session.errorPipe.fileHandleForWriting.closeFile()
            return TimedProcessLaunch(
                processID: processID,
                processGroupID: TimedProcessSpawner.processGroupID(for: processID) ?? processID
            )
        } catch {
            failLaunch(error, session: session)
            return nil
        }
    }

    private func failLaunch(_ error: any Error, session: TimedProcessRunSession) {
        session.outputPipe.fileHandleForWriting.closeFile()
        session.errorPipe.fileHandleForWriting.closeFile()
        guard session.state.markResumedIfNeeded() else { return }
        session.outputPipe.fileHandleForReading.readabilityHandler = nil
        session.errorPipe.fileHandleForReading.readabilityHandler = nil
        session.outputPipe.fileHandleForReading.closeFile()
        session.errorPipe.fileHandleForReading.closeFile()
        session.continuation.resume(throwing: TimedProcessError.launchFailed(
            executablePath: session.configuration.executablePath,
            message: String(describing: error)
        ))
    }

    private func scheduleExitWaiter(
        launch: TimedProcessLaunch,
        state: TimedProcessCompletionBox,
        pipeDrainGraceSeconds: Double,
        terminationGraceSeconds: Double,
        finalizeIfReady: @escaping @Sendable (_ force: Bool) -> Void,
        scheduleForcedFinalize: @escaping @Sendable () -> Void
    ) {
        Thread {
            let exitCode = TimedProcessSpawner.waitForProcessExit(processID: launch.processID)
            Task.detached { @Sendable in
                state.markProcessTerminated(exitCode: exitCode)
                await Self.waitForPipeDrainIfNeeded(state: state, pipeDrainGraceSeconds: pipeDrainGraceSeconds)
                await Self.cleanupProcessGroupAfterExitIfNeeded(
                    launch: launch,
                    terminationGraceSeconds: terminationGraceSeconds
                )
                state.markProcessGroupCleanupComplete()
                finalizeIfReady(false)
                scheduleForcedFinalize()
            }
        }.start()
    }

    private func scheduleDeadlineMonitor(
        launch: TimedProcessLaunch,
        state: TimedProcessCompletionBox,
        timeoutSeconds: Double,
        terminationGraceSeconds: Double,
        cancellationCheck: (@Sendable () async throws -> Bool)?,
        scheduleForcedFinalize: @escaping @Sendable () -> Void
    ) {
        Task.detached { @Sendable in
            let signalled = await Self.monitorUntilDeadline(
                launch: launch,
                state: state,
                timeoutSeconds: timeoutSeconds,
                cancellationCheck: cancellationCheck
            )
            guard signalled else { return }
            await Self.killAfterGraceIfStillRunning(
                launch: launch,
                terminationGraceSeconds: terminationGraceSeconds
            )
            scheduleForcedFinalize()
        }
    }

    private static func drainAvailableData(
        from handle: FileHandle,
        into buffer: TimedProcessOutputBuffer,
        markClosed: @escaping @Sendable () -> Void,
        finalizeIfReady: @escaping @Sendable (_ force: Bool) -> Void
    ) {
        let data = handle.availableData
        if data.isEmpty {
            handle.readabilityHandler = nil
            markClosed()
            finalizeIfReady(false)
        } else {
            buffer.append(data)
        }
    }

    private static func waitForPipeDrainIfNeeded(
        state: TimedProcessCompletionBox,
        pipeDrainGraceSeconds: Double
    ) async {
        guard !state.pipesClosed else { return }
        do {
            try await sleep(seconds: pipeDrainGraceSeconds)
        } catch {
            return
        }
    }

    private static func cleanupProcessGroupAfterExitIfNeeded(
        launch: TimedProcessLaunch,
        terminationGraceSeconds: Double
    ) async {
        guard TimedProcessSpawner.isProcessGroupAlive(launch.processGroupID) else { return }
        let didSignalProcessGroup = TimedProcessSpawner.sendSignalToProcessGroup(
            processID: launch.processID,
            processGroupID: launch.processGroupID,
            signal: SIGTERM
        )
        guard didSignalProcessGroup else { return }
        do {
            try await sleep(seconds: terminationGraceSeconds)
        } catch {
            return
        }
        if TimedProcessSpawner.isProcessGroupAlive(launch.processGroupID) {
            _ = TimedProcessSpawner.sendSignalToProcessGroup(
                processID: launch.processID,
                processGroupID: launch.processGroupID,
                signal: SIGKILL
            )
        }
    }

    private static func monitorUntilDeadline(
        launch: TimedProcessLaunch,
        state: TimedProcessCompletionBox,
        timeoutSeconds: Double,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async -> Bool {
        let startedAt = Date()
        while true {
            do {
                try await sleep(seconds: 0.1)
            } catch {
                return false
            }
            if state.shouldStopMonitoring { return false }
            if let cancellationCheck {
                do {
                    if try await cancellationCheck() {
                        signalDeadline(launch: launch, state: state, markDeadline: state.markCancelled)
                        return true
                    }
                } catch {
                    signalDeadline(launch: launch, state: state) {
                        state.markCancellationCheckFailed(String(describing: error))
                    }
                    return true
                }
            }
            if Date().timeIntervalSince(startedAt) >= timeoutSeconds {
                signalDeadline(launch: launch, state: state, markDeadline: state.markTimedOut)
                return true
            }
        }
    }

    private static func signalDeadline(
        launch: TimedProcessLaunch,
        state: TimedProcessCompletionBox,
        markDeadline: @escaping @Sendable () -> Void
    ) {
        markDeadline()
        _ = TimedProcessSpawner.sendSignalToProcessGroup(
            processID: launch.processID,
            processGroupID: launch.processGroupID,
            signal: SIGTERM
        )
    }

    private static func killAfterGraceIfStillRunning(
        launch: TimedProcessLaunch,
        terminationGraceSeconds: Double
    ) async {
        do {
            try await sleep(seconds: terminationGraceSeconds)
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

    private static func sleep(seconds: Double) async throws {
        let nanoseconds = UInt64((max(0, seconds) * 1_000_000_000).rounded())
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func drainAvailableData(from handle: FileHandle) -> Data {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let fileDescriptor = handle.fileDescriptor
        let existingFlags = fcntl(fileDescriptor, F_GETFL)
        if existingFlags >= 0 {
            _ = fcntl(fileDescriptor, F_SETFL, existingFlags | O_NONBLOCK)
        }
        defer {
            if existingFlags >= 0 {
                _ = fcntl(fileDescriptor, F_SETFL, existingFlags)
            }
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(fileDescriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if readCount > 0 {
                data.append(buffer, count: readCount)
                continue
            }
            if readCount == 0 || errno == EAGAIN || errno == EWOULDBLOCK {
                break
            }
            break
        }
        return data
        #else
        return Data()
        #endif
    }

    private static func utf8String(from data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }
}
