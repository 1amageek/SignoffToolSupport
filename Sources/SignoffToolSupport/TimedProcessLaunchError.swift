import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

enum TimedProcessLaunchError: Error, CustomStringConvertible {
    case posixFailure(operation: String, code: Int32)
    case unsupportedPlatform

    var description: String {
        switch self {
        case .posixFailure(let operation, let code):
            return "\(operation) failed with errno \(code): \(String(cString: strerror(code)))"
        case .unsupportedPlatform:
            return "Process groups are not supported on this platform"
        }
    }
}
