import Foundation

struct TimedProcessRunSession {
    let configuration: TimedProcessRunConfiguration
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let stdoutBuffer = TimedProcessOutputBuffer()
    let stderrBuffer = TimedProcessOutputBuffer()
    let state = TimedProcessCompletionBox()
    let continuation: CheckedContinuation<TimedProcessResult, any Error>
}
