import Foundation
import Network

@MainActor
final class PingService {

    static let shared = PingService()
    private init() {}

    func ping(server: String, port: UInt16) async -> Int? {
        let host = NWEndpoint.Host(server)
        let p    = NWEndpoint.Port(rawValue: port) ?? 443
        let conn = NWConnection(host: host, port: p, using: .tcp)

        return await withCheckedContinuation { cont in
            let box = ResultBox(continuation: cont)
            let start = Date()

            let timeout = DispatchWorkItem { box.finish(nil, conn: conn) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel()
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    box.finish(ms, conn: conn)
                case .failed:
                    timeout.cancel()
                    box.finish(nil, conn: conn)
                default: break
                }
            }
            conn.start(queue: .global())
        }
    }
}

private final class ResultBox: @unchecked Sendable {
    private let continuation: CheckedContinuation<Int?, Never>
    private var done = false
    private let lock = NSLock()

    init(continuation: CheckedContinuation<Int?, Never>) {
        self.continuation = continuation
    }

    func finish(_ ms: Int?, conn: NWConnection) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        conn.cancel()
        continuation.resume(returning: ms)
    }
}
