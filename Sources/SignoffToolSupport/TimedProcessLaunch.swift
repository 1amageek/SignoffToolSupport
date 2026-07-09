import Foundation

struct TimedProcessLaunch: Sendable {
    let processID: pid_t
    let processGroupID: pid_t
}
