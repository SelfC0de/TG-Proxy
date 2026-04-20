import Foundation

@MainActor
final class PingService {

    static let shared = PingService()
    private init() {}

    // URLSession that does NOT follow redirects and accepts any server response
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 6
        cfg.timeoutIntervalForResource = 6
        cfg.waitsForConnectivity = false
        cfg.allowsCellularAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        return URLSession(configuration: cfg, delegate: PingDelegate.shared, delegateQueue: nil)
    }()

    /// Returns round-trip time in ms, or nil if unreachable within 6 seconds.
    /// Sends a minimal HTTP GET to http://server:port.
    /// MTProto servers respond with 400/any status = TCP connection succeeded = server alive.
    func ping(server: String, port: UInt16) async -> Int? {
        guard let url = URL(string: "http://\(server):\(port)/") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("TGProxy/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 6

        let start = Date()
        do {
            let (_, response) = try await session.data(for: req)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            // Any HTTP response means TCP connection succeeded
            if response is HTTPURLResponse {
                return max(1, ms)
            }
            return nil
        } catch let err as URLError {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            switch err.code {
            // These mean TCP connected but server rejected HTTP (expected for MTProto)
            case .badServerResponse,
                 .cannotParseResponse,
                 .zeroByteResource:
                return max(1, ms)
            // These mean the port is open but response was unexpected
            case .cancelled:
                return nil
            // Timeout / no route / refused = server down
            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}

// Delegate: accept any SSL cert, don't follow redirects, treat any data as success
private final class PingDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    static let shared = PingDelegate()

    // Accept self-signed certs (MTProto servers may use custom certs)
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // Don't follow redirects
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
