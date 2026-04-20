import WebKit
import Combine

@MainActor
final class SourcesFetcher: NSObject, ObservableObject {

    @Published var proxies: [ProxyItem] = []
    @Published var loadState: SourceLoadState = .idle
    @Published var isPinging = false

    private var webViews: [WKWebView] = []
    private var pendingCount = 0

    fileprivate struct WebSource {
        let url: String
        let name: String
        let waitSeconds: Double
        let jsExtract: String
    }

    private var webSources: [WebSource] {
        let speedupJS = """
        (function(){
            var r=[];
            var els=document.querySelectorAll('.share-url');
            for(var i=0;i<els.length;i++){
                var t=els[i].textContent.trim();
                if(t.indexOf('tg://proxy')===0) r.push(t);
            }
            return JSON.stringify(r);
        })()
        """

        let mtproxyTG3JS = """
        (function(){
            var r=[];
            var cards=document.querySelectorAll('.proxy-card');
            for(var i=0;i<cards.length;i++){
                var a=cards[i].querySelector('a[href]');
                if(!a) continue;
                var h=a.getAttribute('href');
                if(!h||h.indexOf('tg://')<0) continue;
                var country='';
                var nm=cards[i].querySelector('.proxy-name');
                if(nm) country=nm.textContent.trim();
                r.push(JSON.stringify({url:h,country:country}));
            }
            return JSON.stringify(r);
        })()
        """

        let widumJS = """
        (function(){
            var r=[];
            var items=document.querySelectorAll('.proxy-list .proxy-item');
            for(var i=0;i<items.length;i++){
                var a=items[i].querySelector('a[href]');
                if(!a) continue;
                var h=a.getAttribute('href');
                if(!h||h.indexOf('tg://')<0) continue;
                var country='';
                var spans=items[i].querySelectorAll('.proxy-country span');
                if(spans.length>1) country=spans[spans.length-1].textContent.trim();
                r.push(JSON.stringify({url:h,country:country}));
            }
            return JSON.stringify(r);
        })()
        """

        // MTProbe: click "load more" until gone, then collect all.
        // Regex uses string concat to avoid Swift escape issues: "/" + "([A-Z]{2})" + "\\.svg$"
        let mtprobeJS = """
        (function(){
            var clickAndWait=function(resolve){
                var btn=document.getElementById('load_more_btn');
                if(!btn||btn.style.display==='none'||btn.disabled){
                    setTimeout(resolve,1200);
                    return;
                }
                btn.click();
                setTimeout(function(){clickAndWait(resolve);},2000);
            };
            return new Promise(function(resolve){
                clickAndWait(function(){
                    var r=[];
                    var cards=document.querySelectorAll('#servers_container .server-card');
                    for(var i=0;i<cards.length;i++){
                        var el=cards[i].querySelector('[data-link]');
                        if(!el) continue;
                        var h=el.getAttribute('data-link');
                        if(!h||h.indexOf('tg://')<0) continue;
                        var country='';
                        var flag=cards[i].querySelector('img.flag');
                        if(flag){
                            var src=flag.getAttribute('src')||'';
                            var parts=src.split('/');
                            var last=parts[parts.length-1];
                            if(last.length>=6) country=last.substring(0,2);
                        }
                        r.push(JSON.stringify({url:h,country:country}));
                    }
                    resolve(JSON.stringify(r));
                });
            });
        })()
        """

        return [
            WebSource(url: "https://speedupnet.vip/proxy",              name: "SpeedUpNet", waitSeconds: 4, jsExtract: speedupJS),
            WebSource(url: "https://mtproxytg3.vercel.app/",             name: "MTProxyTG3", waitSeconds: 6, jsExtract: mtproxyTG3JS),
            WebSource(url: "https://widum.ru/proxy/",                    name: "Widum",      waitSeconds: 6, jsExtract: widumJS),
            WebSource(url: "https://mtprobe.cyou/free-mtproto-proxies?max_ping=100&ee_mask=true",
                      name: "MTProbe", waitSeconds: 3, jsExtract: mtprobeJS),
        ]
    }

    // MARK: - Public

    func loadAll() {
        proxies = []
        loadState = .loading
        let sources = webSources
        pendingCount = sources.count + 2  // +yandex +kakfix

        fetchYandex()
        fetchKakfix()
        for src in sources { loadWebSource(src) }
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

    // MARK: - Yandex

    private func fetchYandex() {
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://storage.yandexcloud.net/qlinks/proxy.html")!)
                req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)
                let html = String(data: data, encoding: .utf8) ?? ""
                let items = parseByHref(html, source: "Яндекс")
                streamAppend(items)
            } catch {}
            finish()
        }
    }

    // MARK: - KakFix (10 pages parallel)

    private func fetchKakfix() {
        Task {
            await withTaskGroup(of: [ProxyItem].self) { group in
                for page in 1...10 {
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        return await self.fetchKakfixPage(page)
                    }
                }
                // Stream results page by page as they arrive
                for await items in group {
                    if !items.isEmpty { streamAppend(items) }
                }
            }
            finish()
        }
    }

    private func fetchKakfixPage(_ page: Int) async -> [ProxyItem] {
        let urlStr = page == 1
            ? "https://kakfix.online/ru/proxies"
            : "https://kakfix.online/ru/proxies?page=\(page)"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("https://kakfix.online", forHTTPHeaderField: "Referer")
        req.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""
            return parseKakfix(html)
        } catch { return [] }
    }

    private func parseKakfix(_ html: String) -> [ProxyItem] {
        var result: [ProxyItem] = []
        let blocks = html.components(separatedBy: "proxy-card__actions")
        guard blocks.count > 1 else { return [] }

        // Countries: text after emoji span closing tag
        var countries: [String] = []
        if let re = try? NSRegularExpression(
            pattern: "proxy-card__country[^>]*>[^<]*</span>\\s*([A-Za-z\\u00C0-\\u024F ]+)"
        ) {
            let ns = html as NSString
            for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
                let c = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !c.isEmpty { countries.append(c) }
            }
        }

        let hrefRe = try? NSRegularExpression(pattern: "href=\"(tg://proxy\\?[^\"]+)\"")
        var idx = 0
        for block in blocks.dropFirst() {
            let ns = block as NSString
            if let re = hrefRe,
               let m = re.firstMatch(in: block, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: m.range(at: 1))
                    .replacingOccurrences(of: "&amp;", with: "&")
                if var item = parseProxyURL(raw, source: "KakFix") {
                    item.countryName = idx < countries.count ? countries[idx] : ""
                    result.append(item)
                }
            }
            idx += 1
        }
        return result
    }

    // MARK: - WKWebView sources

    private func loadWebSource(_ src: WebSource) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webViews.append(wv)
        let ctx = WebContext(source: src, webView: wv, owner: self)
        objc_setAssociatedObject(wv, &WebContext.key, ctx, .OBJC_ASSOCIATION_RETAIN)
        var req = URLRequest(url: URL(string: src.url)!)
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        req.timeoutInterval = 30
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
                                let href = url.replacingOccurrences(of: "&amp;", with: "&")
                                if var item = self.parseProxyURL(href, source: source.name) {
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
                        if !items.isEmpty { self.streamAppend(items) }
                    }
                } catch {}
                self.finish()
            }
        }
    }

    // MARK: - Streaming append (shows results progressively)

    private func streamAppend(_ items: [ProxyItem]) {
        let existingKeys = Set(proxies.map { "\($0.server):\($0.port)" })
        let fresh = items.filter { !existingKeys.contains("\($0.server):\($0.port)") }
        guard !fresh.isEmpty else { return }
        proxies.append(contentsOf: fresh)
        // Show partial results immediately
        if case .loading = loadState { loadState = .done }
    }

    fileprivate func finish() {
        pendingCount -= 1
        if pendingCount <= 0 {
            if proxies.isEmpty { loadState = .error("Серверы не найдены") }
            webViews.removeAll()
        }
    }

    // MARK: - Helpers

    private func parseByHref(_ html: String, source: String) -> [ProxyItem] {
        var result: [ProxyItem] = []
        guard let re = try? NSRegularExpression(pattern: "href=\"(tg://proxy\\?[^\"]+)\"") else { return [] }
        let ns = html as NSString
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let href = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
            if let item = parseProxyURL(href, source: source) { result.append(item) }
        }
        return result
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
        guard let server = params["server"], let port = params["port"],
              !server.isEmpty, !port.isEmpty else { return nil }
        return ProxyItem(server: server, port: port, tgURL: clean, sourceName: source)
    }
}

// MARK: - WebContext

private class WebContext: NSObject, WKNavigationDelegate {
    static var key = "wck"
    let source: SourcesFetcher.WebSource
    weak var webView: WKWebView?
    weak var owner: SourcesFetcher?

    init(source: SourcesFetcher.WebSource, webView: WKWebView, owner: SourcesFetcher) {
        self.source = source; self.webView = webView; self.owner = owner
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
        Task { @MainActor [weak self] in self?.owner?.finish() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.owner?.finish() }
    }
}
