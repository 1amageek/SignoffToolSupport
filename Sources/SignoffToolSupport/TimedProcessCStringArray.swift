import Foundation

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

final class TimedProcessCStringArray {
    private var pointers: [UnsafeMutablePointer<CChar>?] = []

    init(_ strings: [String]) throws {
        for string in strings {
            guard let pointer = strdup(string) else {
                throw TimedProcessLaunchError.posixFailure(operation: "strdup", code: ENOMEM)
            }
            pointers.append(pointer)
        }
        pointers.append(nil)
    }

    deinit {
        for pointer in pointers {
            free(pointer)
        }
    }

    func withUnsafeMutablePointers<R>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> R
    ) throws -> R {
        try pointers.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw TimedProcessLaunchError.posixFailure(operation: "argv buffer", code: EINVAL)
            }
            return try body(baseAddress)
        }
    }
}
