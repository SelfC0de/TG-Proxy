import WebKit
import Combine

// MARK: - Sources fetcher

@MainActor
final class SourcesFetcher: NSObject, ObservableObject {

    @Published var proxies: [ProxyItem] = []
    @Published var loadState: SourceLoadState = .idle
    @Published var isPinging = false

    private var webViews: [WKWebView] = []
    private var pendingWebSources = 0

    // fileprivate so WebContext (extension in same file) can access
    fileprivate struct WebSource {
        let url: String
        let name: String
        let waitSeconds: Double
        let jsExtract: String
    }

    private let webSources: [WebSource] = [
        WebSource(
            url: "https://speedupnet.vip/proxy",
            name: "SpeedUpNet",
            waitSeconds: 3,
            jsExtract: """
            (function(){
                var r=[];
                document.querySelectorAll('.share-url').forEach(function(el){
                    var t=el.textContent.trim();
                    if(t.startsWith('tg://proxy')) r.push(t);
                });
                return JSON.stringify(r);
            })()
            """
        ),
        WebSource(
            url: "https://mtproxytg3.vercel.app/",
            name: "MTProxyTG3",
            waitSeconds: 4,
            jsExtract: """
            (function(){
                var r=[];
                document.querySelectorAll('.proxy-grid a[href^="tg://proxy"]').forEach(function(a){
                    r.push(a.href);
                });
                return JSON.stringify(r);
            })()
            """
        ),
        WebSource(
            url: "https://widum.ru/proxy/",
            name: "Widum",
            waitSeconds: 4,
            jsExtract: """
            (function(){
                var r=[];
                document.querySelectorAll('.proxy-list .proxy-item a[href^="tg://proxy"]').forEach(function(a){
                    var country='';
                    var span=a.closest('.proxy-item')?.querySelector('.proxy-country span:last-child');
                    if(span) country=span.textContent.trim();
                    r.push(JSON.stringify({url:a.href,country:country}));
                });
                return JSON.stringify(r);
            })()
            """
        ),
    ]

    // MARK: - Public

    func loadAll() {
        proxies = []
        loadState = .loading
        pendingWebSources = webSources.count + 1

        fetchYandex()
        for src in webSources {
            loadWebSource(src)
        }
    }

    func pingAll() {
        guard !proxies.isEmpty else { return }
        isPinging = true
        let items = proxies
        Task {
            await withTaskGroup(of: (UUID, Int?).self) { group in
                for item in items {
                    group.addTask { [weak self] in
                        guard let self else { return (item.id, nil) }
                        await MainActor.run {
                            if let idx = self.proxies.firstIndex(where: { $0.id == item.id }) {
                                self.proxies[idx].pingState = .pinging
                            }
                        }
                        let port = UInt16(item.port) ?? 443
                        let ms = await PingService.shared.ping(server: item.server, port: port)
                        return (item.id, ms)
                    }
                }
                for await (id, ms) in group {
                    if let idx = self.proxies.firstIndex(where: { $0.id == id }) {
                        self.proxies[idx].pingMs = ms
                        self.proxies[idx].pingState = ms != nil ? .done : .failed
                    }
                }
            }
            self.proxies.sort {
                switch ($0.pingState, $1.pingState) {
                case (.done, .done): return ($0.pingMs ?? 9999) < ($1.pingMs ?? 9999)
                case (.done, _):     return true
                case (_, .done):     return false
                default:             return false
                }
            }
            self.isPinging = false
        }
    }

    // MARK: - Yandex (URLSession, static HTML)

    private func fetchYandex() {
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://storage.yandexcloud.net/qlinks/proxy.html")!)
                req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: req)
                let html = String(data: data, encoding: .utf8) ?? ""
                appendProxies(parseYandex(html))
            } catch {}
            sourceDidFinish()
        }
    }

    private func parseYandex(_ html: String) -> [ProxyItem] {
        var result: [ProxyItem] = []
        guard let regex = try? NSRegularExpression(pattern: #"href="(tg://proxy\?[^"]+)""#) else { return [] }
        let ns = html as NSString
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            if let item = parseProxyURL(href, source: "Яндекс") { result.append(item) }
        }
        return result
    }

    // MARK: - WKWebView sources

    private func loadWebSource(_ src: WebSource) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        webViews.append(wv)

        let ctx = WebContext(source: src, webView: wv, owner: self)
        objc_setAssociatedObject(wv, &WebContext.key, ctx, .OBJC_ASSOCIATION_RETAIN)

        var req = URLRequest(url: URL(string: src.url)!)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        wv.load(req)
    }

    fileprivate func webSourceDidLoad(_ wv: WKWebView, source: WebSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + source.waitSeconds) { [weak self, weak wv] in
            guard let self, let wv else { return }
            Task { @MainActor in
                do {
                    let result = try await wv.evaluateJavaScript(source.jsExtract)
                    if let jsonStr = result as? String,
                       let data = jsonStr.data(using: .utf8),
                       let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                        var items: [ProxyItem] = []
                        for raw in arr {
                            if let inner = raw.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: inner) as? [String: String],
                               let url = obj["url"] {
                                if var item = self.parseProxyURL(url, source: source.name) {
                                    item.countryName = obj["country"] ?? ""
                                    items.append(item)
                                }
                            } else {
                                let href = raw.replacingOccurrences(of: "&amp;", with: "&")
                                if let item = self.parseProxyURL(href, source: source.name) {
                                    items.append(item)
                                }
                            }
                        }
                        self.appendProxies(items)
                    }
                } catch {}
                self.sourceDidFinish()
            }
        }
    }

    fileprivate func sourceDidFinish() {
        pendingWebSources -= 1
        if pendingWebSources <= 0 {
            loadState = proxies.isEmpty ? .error("Ничего не загружено") : .done
            webViews.removeAll()
        }
    }

    // MARK: - Helpers

    private func appendProxies(_ items: [ProxyItem]) {
        let existing = Set(proxies.map { $0.tgURL })
        proxies.append(contentsOf: items.filter { !existing.contains($0.tgURL) })
    }

    func parseProxyURL(_ href: String, source: String) -> ProxyItem? {
        let clean = href.replacingOccurrences(of: "&amp;", with: "&")
        guard let url = URL(string: clean),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let params = Dictionary(
            uniqueKeysWithValues: (comps.queryItems ?? []).compactMap { i -> (String, String)? in
                guard let v = i.value else { return nil }
                return (i.name, v)
            }
        )
        guard let server = params["server"], let port = params["port"] else { return nil }
        return ProxyItem(server: server, port: port, tgURL: clean, sourceName: source)
    }
}

// MARK: - WebContext (navigation delegate per WKWebView)

private class WebContext: NSObject, WKNavigationDelegate {
    static var key = "wck"
    let source: SourcesFetcher.WebSource
    weak var webView: WKWebView?
    weak var owner: SourcesFetcher?

    init(source: SourcesFetcher.WebSource, webView: WKWebView, owner: SourcesFetcher) {
        self.source = source
        self.webView = webView
        self.owner = owner
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, let owner = self.owner else { return }
            owner.webSourceDidLoad(webView, source: self.source)
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.owner?.sourceDidFinish() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.owner?.sourceDidFinish() }
    }
}
