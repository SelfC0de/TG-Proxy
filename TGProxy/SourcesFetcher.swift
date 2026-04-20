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

    // Only JS-rendered sources here
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

        // MTProbe: click "load more" until gone, collect all.
        // Country from flag img src: split by '/', take last part, first 2 chars = country code
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
            WebSource(url: "https://speedupnet.vip/proxy",
                      name: "SpeedUpNet", waitSeconds: 4, jsExtract: speedupJS),
            WebSource(url: "https://mtproxytg3.vercel.app/",
                      name: "MTProxyTG3", waitSeconds: 6, jsExtract: mtproxyTG3JS),
            WebSource(url: "https://mtprobe.cyou/free-mtproto-proxies?max_ping=100&ee_mask=true",
                      name: "MTProbe", waitSeconds: 3, jsExtract: mtprobeJS),
        ]
    }

    // MARK: - Public

    func loadAll() {
        proxies = []
        loadState = .loading
        let sources = webSources
        // URLSession: yandex + kakfix + widum = 3; WKWebView sources = sources.count
        pendingCount = sources.count + 4  // +yandex +kakfix +widum +soliSpirit

        fetchYandex()
        fetchKakfix()
        fetchWidum()
        fetchSoliSpirit()
        for src in sources { loadWebSource(src) }
    }

    func pingSingle(_ item: ProxyItem) {
        guard let idx = proxies.firstIndex(where: { $0.id == item.id }) else { return }
        proxies[idx].pingState = .pinging
        Task {
            let port = UInt16(item.port) ?? 443
            let ms = await PingService.shared.ping(server: item.server, port: port)
            if let i = self.proxies.firstIndex(where: { $0.id == item.id }) {
                self.proxies[i].pingMs = ms
                self.proxies[i].pingState = ms != nil ? .done : .failed
            }
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
            // Remove unreachable, then sort by latency
            self.proxies.removeAll { $0.pingState == .failed }
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

    // MARK: - SoliSpirit GitHub (plain text, one URL per line)

    private func fetchSoliSpirit() {
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://raw.githubusercontent.com/SoliSpirit/mtproto/refs/heads/master/all_proxies.txt")!)
                req.setValue("curl/7.88", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)
                let text = String(data: data, encoding: .utf8) ?? ""
                var items: [ProxyItem] = []
                for line in text.components(separatedBy: .newlines) {
                    let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !raw.isEmpty else { continue }
                    // Convert https://t.me/proxy?... -> tg://proxy?...
                    let tg = raw
                        .replacingOccurrences(of: "https://t.me/proxy?", with: "tg://proxy?")
                        .replacingOccurrences(of: "http://t.me/proxy?",  with: "tg://proxy?")
                    guard tg.hasPrefix("tg://proxy?") else { continue }
                    if let item = parseProxyURL(tg, source: "GitHub") {
                        items.append(item)
                    }
                }
                streamAppend(items)
            } catch {}
            finish()
        }
    }

    // MARK: - Yandex (static HTML, URLSession)

    private func fetchYandex() {
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://storage.yandexcloud.net/qlinks/proxy.html")!)
                req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)
                let html = String(data: data, encoding: .utf8) ?? ""
                streamAppend(parseByHref(html, source: "Яндекс"))
            } catch {}
            finish()
        }
    }

    // MARK: - KakFix (JSON API — returns all 200 proxies in one request)

    private func fetchKakfix() {
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://kakfix.online/api/proxies.php")!)
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
                             forHTTPHeaderField: "User-Agent")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("https://kakfix.online/ru/proxies", forHTTPHeaderField: "Referer")
                req.timeoutInterval = 20
                let (data, _) = try await URLSession.shared.data(for: req)
                let items = parseKakfixJSON(data)
                streamAppend(items)
            } catch {}
            finish()
        }
    }

    private func parseKakfixJSON(_ data: Data) -> [ProxyItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = json["success"] as? Bool, success,
              let dataObj = json["data"] as? [String: Any],
              let proxies = dataObj["proxies"] as? [[String: Any]] else { return [] }

        return proxies.compactMap { p -> ProxyItem? in
            guard let host   = p["host"]   as? String,
                  let portAny = p["port"],
                  let secret = p["secret"] as? String,
                  !host.isEmpty, !secret.isEmpty else { return nil }
            let port: String
            if let pi = portAny as? Int        { port = String(pi) }
            else if let ps = portAny as? String { port = ps }
            else { return nil }
            let tgURL = "tg://proxy?server=\(host)&port=\(port)&secret=\(secret)"
            var item = ProxyItem(server: host, port: port, tgURL: tgURL, sourceName: "KakFix")
            item.countryName = (p["country_name"] as? String) ?? ""
            return item
        }
    }

    // MARK: - Widum (static HTML, URLSession)

    private func fetchWidum() {
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://widum.ru/proxy/")!)
                req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
                             forHTTPHeaderField: "User-Agent")
                req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 15
                let (data, _) = try await URLSession.shared.data(for: req)
                let html = String(data: data, encoding: .utf8) ?? ""
                streamAppend(parseWidum(html))
            } catch {}
            finish()
        }
    }

    private func parseWidum(_ html: String) -> [ProxyItem] {
        var result: [ProxyItem] = []
        // Split by proxy-item blocks
        let blocks = html.components(separatedBy: "class=\"proxy-item\"")
        guard blocks.count > 1 else { return [] }

        let hrefRe    = try? NSRegularExpression(pattern: "href=\"(tg://proxy\\?[^\"]+)\"")
        let countryRe = try? NSRegularExpression(pattern: "<span[^>]*>[^<]{1,30}</span>\\s*</div>\\s*</div>")
        // Simpler country: data-country-code="XX"
        let codeRe    = try? NSRegularExpression(pattern: "data-country-code=\"([a-z]{2})\"")

        for block in blocks.dropFirst() {
            let ns = block as NSString
            let range = NSRange(location: 0, length: ns.length)

            guard let re = hrefRe,
                  let m = re.firstMatch(in: block, range: range) else { continue }
            let href = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
            guard var item = parseProxyURL(href, source: "Widum") else { continue }

            // Country from data-country-code attribute
            if let cr = codeRe,
               let cm = cr.firstMatch(in: block, range: range) {
                item.countryName = ns.substring(with: cm.range(at: 1)).uppercased()
            }
            result.append(item)
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

    // MARK: - Streaming append

    private func streamAppend(_ items: [ProxyItem]) {
        let existingKeys = Set(proxies.map { "\($0.server):\($0.port)" })
        let fresh = items.filter { !existingKeys.contains("\($0.server):\($0.port)") }
        guard !fresh.isEmpty else { return }
        proxies.append(contentsOf: fresh)
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
