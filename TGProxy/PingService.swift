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
            let start = Date()
            var finished = false

            let timeout = DispatchWorkItem {
                if !finished { finished = true; conn.cancel(); cont.resume(returning: nil) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !finished {
                        finished = true
                        timeout.cancel()
                        let ms = Int(Date().timeIntervalSince(start) * 1000)
                        conn.cancel()
                        cont.resume(returning: ms)
                    }
                case .failed:
                    if !finished {
                        finished = true
                        timeout.cancel()
                        conn.cancel()
                        cont.resume(returning: nil)
                    }
                default: break
                }
            }
            conn.start(queue: .global())
        }
    }
}
