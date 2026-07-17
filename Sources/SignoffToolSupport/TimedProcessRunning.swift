import Foundation

public protocol TimedProcessRunning: Sendable {
    func run(
        process: Process,
        cancellationCheck: (@Sendable () async throws -> Bool)?
    ) async throws -> TimedProcessResult
}

extension TimedProcessRunner: TimedProcessRunning {}
