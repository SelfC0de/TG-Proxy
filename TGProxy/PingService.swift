import Foundation
import Network

@MainActor
final class PingService {

    static let shared = PingService()
    private init() {}

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 6
        cfg.timeoutIntervalForResource = 6
        cfg.waitsForConnectivity       = false
        cfg.allowsCellularAccess       = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess   = true
        return URLSession(configuration: cfg,
                         delegate: PingDelegate.shared,
                         delegateQueue: nil)
    }()

    func ping(server: String, port: UInt16) async -> Int? {
        // Try HTTP first — MTProto servers respond with 400/426 which proves TCP is open
        if let ms = await pingHTTP(server: server, port: port) { return ms }
        // Fallback: raw NWConnection TCP (handles cases where HTTP gets no response at all)
        return await pingTCP(server: server, port: port)
    }

    // MARK: - HTTP probe

    private func pingHTTP(server: String, port: UInt16) async -> Int? {
        guard let url = URL(string: "http://\(server):\(port)/") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod  = "GET"
        req.timeoutInterval = 5
        req.setValue("TGProxy/1.0", forHTTPHeaderField: "User-Agent")

        let start = Date()
        do {
            let (_, response) = try await session.data(for: req)
            // Any HTTP response = TCP connected = server alive
            if response is HTTPURLResponse {
                return max(1, Int(Date().timeIntervalSince(start) * 1000))
            }
            return nil
        } catch let err as URLError {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            // These error codes mean TCP DID connect but the server rejected HTTP
            // (expected for MTProto): server is ALIVE
            let reachableCodes: Set<URLError.Code> = [
                .badServerResponse,      // server sent non-HTTP or malformed response
                .cannotParseResponse,    // response couldn't be parsed
                .zeroByteResource,       // empty response body
                .dataNotAllowed,         // data returned but not usable
                .unsupportedURL,         // server closed without response (some MTProto)
            ]
            if reachableCodes.contains(err.code) {
                return max(1, ms)
            }
            // HTTP status errors (400, 426, etc) — URLSession on iOS wraps these
            // as URLError with underlying NSURLError; check the raw code
            if err.code == .cannotDecodeRawData || err.code == .cannotDecodeContentData {
                return max(1, ms)
            }
            // Truly unreachable: timeout, no route, refused, DNS fail
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - TCP fallback via NWConnection

    private func pingTCP(server: String, port: UInt16) async -> Int? {
        let host = NWEndpoint.Host(server)
        let p    = NWEndpoint.Port(rawValue: port) ?? 443
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = []
        let conn = NWConnection(host: host, port: p, using: params)

        return await withCheckedContinuation { cont in
            let box = ResultBox(continuation: cont)
            let start = Date()

            let timeout = DispatchWorkItem { box.finish(nil, conn: conn) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel()
                    let ms = max(1, Int(Date().timeIntervalSince(start) * 1000))
                    box.finish(ms, conn: conn)
                case .failed:
                    timeout.cancel()
                    box.finish(nil, conn: conn)
                case .waiting:
                    // .waiting means no route / unreachable — treat as failed
                    timeout.cancel()
                    box.finish(nil, conn: conn)
                default:
                    break
                }
            }
            conn.start(queue: .global())
        }
    }
}

// MARK: - Delegate

private final class PingDelegate: NSObject,
    URLSessionDataDelegate,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    static let shared = PingDelegate()

    // Accept any TLS cert (MTProto servers often use self-signed)
    nonisolated func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // Don't follow redirects — measure first hop only
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// MARK: - Thread-safe continuation box

private final class ResultBox: @unchecked Sendable {
    private let continuation: CheckedContinuation<Int?, Never>
    private var done = false
    private let lock = NSLock()

    init(continuation: CheckedContinuation<Int?, Never>) {
        self.continuation = continuation
    }

    func finish(_ ms: Int?, conn: NWConnection) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        conn.cancel()
        continuation.resume(returning: ms)
    }
}
