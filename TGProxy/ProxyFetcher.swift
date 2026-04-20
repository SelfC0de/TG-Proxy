import WebKit
import Combine

struct ProxyData {
    let server: String
    let port: String
    let tgURL: String
}

@MainActor
final class ProxyFetcher: NSObject, ObservableObject {

    enum State {
        case idle
        case loading(progress: Double)
        case ready(ProxyData)
        case error(String)
    }

    @Published var state: State = .idle

    private var webView: WKWebView?
    private var timer: Timer?
    private var elapsed: Double = 0
    private let totalWait: Double = 5.0
    private let pageURL = URL(string: "https://mtproto.ru/personal.php")!

    func fetch() {
        cancel()
        state = .loading(progress: 0)
        elapsed = 0

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        webView = wv

        var req = URLRequest(url: pageURL)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        wv.load(req)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        webView?.stopLoading()
        webView = nil
    }

    private func startCountdown() {
        timer?.invalidate()
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsed += 0.1
                let p = min(self.elapsed / self.totalWait, 1.0)
                if case .loading = self.state {
                    self.state = .loading(progress: p)
                }
                if self.elapsed >= self.totalWait {
                    self.timer?.invalidate()
                    self.timer = nil
                    await self.extractProxy()
                }
            }
        }
    }

    private func extractProxy() async {
        guard let wv = webView else { return }
        let js = """
        (function(){
            var el = document.getElementById('get-message');
            if (!el) return null;
            var a = el.querySelector('a[href^="tg://proxy"]');
            if (!a) return null;
            return a.href;
        })()
        """
        do {
            let result = try await wv.evaluateJavaScript(js)
            guard let href = result as? String, !href.isEmpty else {
                state = .error("Свободных серверов нет. Попробуйте позже.")
                return
            }
            guard let parsed = parseProxy(href) else {
                state = .error("Не удалось разобрать ссылку прокси.")
                return
            }
            state = .ready(parsed)
        } catch {
            state = .error("Ошибка загрузки: \(error.localizedDescription)")
        }
    }

    private func parseProxy(_ href: String) -> ProxyData? {
        guard let url = URL(string: href),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let params = Dictionary(
            uniqueKeysWithValues: (comps.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let v = item.value else { return nil }
                return (item.name, v)
            }
        )
        guard let server = params["server"], let port = params["port"] else { return nil }
        return ProxyData(server: server, port: port, tgURL: href)
    }
}

extension ProxyFetcher: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.startCountdown() }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.state = .error("Ошибка сети: \(error.localizedDescription)") }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.state = .error("Ошибка сети: \(error.localizedDescription)") }
    }
}
