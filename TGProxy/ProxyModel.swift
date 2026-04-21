import Foundation

enum NetworkType: String, Equatable {
    case wifi = "WiFi"
    case lte  = "LTE"
}

struct ProxyItem: Identifiable, Equatable {
    let id = UUID()
    let server: String
    let port: String
    let tgURL: String
    let sourceName: String
    var networkType: NetworkType = .wifi
    var countryName: String = ""
    var countryCode: String = ""
    var pingMs: Int? = nil
    var pingState: PingState = .idle

    enum PingState: Equatable {
        case idle, pinging, done, failed
    }

    var shortServer: String {
        let parts = server.split(separator: ".")
        if parts.count > 3 {
            return "…" + parts.dropFirst().joined(separator: ".")
        }
        return server
    }

    var pingLabel: String {
        switch pingState {
        case .idle:    return "—"
        case .pinging: return "…"
        case .done:    return pingMs.map { "\($0) ms" } ?? "—"
        case .failed:  return "timeout"
        }
    }
}

enum SourceLoadState {
    case idle, loading, done, error(String)
}
