import Foundation
import Synchronization

final class TimedProcessOutputBuffer: Sendable {
    private let storage = Mutex(Data())

    func append(_ data: Data) {
        storage.withLock { $0.append(data) }
    }

    func snapshot() -> Data {
        storage.withLock { $0 }
    }
}
