import Foundation

struct TimedProcessRunConfiguration: Sendable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]?
    let workingDirectory: URL?
    let timeoutSeconds: Double
    let terminationGraceSeconds: Double
    let pipeDrainGraceSeconds: Double
    let cancellationCheck: (@Sendable () async throws -> Bool)?
}
