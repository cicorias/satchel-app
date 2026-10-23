import Foundation
import WebKit

/// Reads a page's metadata the way the capture engine does everywhere else: `captureLink` from `capture.iife.js`,
/// run over the page's DOM in a hidden `WKWebView` (spec §9.2.4).
///
/// - **One request:** the HTML is fetched with an ephemeral `URLSession` (no cookies from Safari or earlier loads, at
///   most `maxBytes`), then loaded into a web view whose content rule blocks every subresource, so nothing else is
///   downloaded.
/// - **No page scripts:** the page's JavaScript is off; the capture script runs in the `.defaultClient` world. With
///   JavaScript off WebKit drops `<script>` elements, JSON-LD included, so those are carried through as hidden
///   `<textarea data-satchel-ld>` elements and turned back into (inert) JSON-LD scripts before `captureLink` runs.
/// - Each load gets a fresh web view; cancelling the task stops it.
@MainActor
public final class WebMetadataLoader: LinkMetadataLoader {
    private let captureScript: String
    private var ruleList: WKContentRuleList?

    /// `captureScript` is the source of `capture.iife.js` (`globalThis.SatchelCapture`).
    public nonisolated init(captureScript: String) {
        self.captureScript = captureScript
    }

    /// The capture bundle shipped in the app (`capture.iife.js`, staged by the WebAssets target).
    public nonisolated static func bundled(in bundle: Bundle = .main) -> WebMetadataLoader? {
        guard let url = bundle.url(forResource: "capture.iife", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WebMetadataLoader(captureScript: source)
    }

    /// Pages larger than this aren't read.
    public nonisolated static let maxBytes = 5 * 1024 * 1024

    public nonisolated func metadata(for url: String) async throws -> LinkMetadata {
        guard let target = URL(string: url), ["http", "https"].contains(target.scheme?.lowercased()) else {
            throw EnrichmentError.load("not a web URL")
        }
        let (html, finalURL) = try await Self.fetchHTML(target)
        return try await metadata(html: html, baseURL: finalURL)
    }

    /// Runs `captureLink` over HTML, with `baseURL` as the page's address. Tests call this with a fixture.
    public func metadata(html: String, baseURL: URL) async throws -> LinkMetadata {
        let prepared = Self.keepingJSONLD(html)
        return try await load { $0.loadHTMLString(prepared, baseURL: baseURL) }
    }

    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = [
            "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1",
            // What Safari on an iPhone sends, so sites serve their normal page.
            "User-Agent":
                "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
        ]
        return URLSession(configuration: configuration)
    }()

    private nonisolated static func fetchHTML(_ url: URL) async throws -> (String, URL) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw EnrichmentError.load(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EnrichmentError.load("HTTP \(http.statusCode)")
        }
        let type = response.mimeType ?? "text/html"
        guard ["text/html", "application/xhtml+xml"].contains(type) else {
            throw EnrichmentError.load("not an HTML page (\(type))")
        }
        guard data.count <= maxBytes else { throw EnrichmentError.load("page larger than \(maxBytes) bytes") }
        let encoding = response.textEncodingName.map {
            String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringConvertIANACharSetNameToEncoding($0 as CFString)))
        }
        let html = encoding.flatMap { String(data: data, encoding: $0) } ?? String(decoding: data, as: UTF8.self)
        return (html, response.url ?? url)
    }

    /// `<script type="application/ld+json">…</script>` → `<textarea data-satchel-ld hidden>…</textarea>`, so the data
    /// survives a parse with JavaScript off. A `</textarea` inside the JSON is escaped so it can't end the element.
    nonisolated static func keepingJSONLD(_ html: String) -> String {
        let pattern = /(?is)<script\b[^>]*\btype\s*=\s*["']?application\/ld\+json["']?[^>]*>(.*?)<\/script\s*>/
        return html.replacing(pattern) { match in
            let json = String(match.output.1).replacing(/(?i)<\/textarea/, with: "<\\/textarea")
            return "<textarea data-satchel-ld hidden>\(json)</textarea>"
        }
    }

    private func load(_ start: (WKWebView) -> WKNavigation?) async throws -> LinkMetadata {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        if let rules = try await blockingRules() { configuration.userContentController.add(rules) }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: configuration)
        let navigation = Navigation()
        view.navigationDelegate = navigation
        defer {
            view.stopLoading()
            view.navigationDelegate = nil
        }
        try await withTaskCancellationHandler {
            try await navigation.wait { _ = start(view) }
        } onCancel: {
            Task { @MainActor in navigation.cancel() }
        }
        try Task.checkCancellation()

        _ = try? await view.callAsyncJavaScript(captureScript, arguments: [:], in: nil, contentWorld: .defaultClient)
        let json: Any?
        do {
            json = try await view.callAsyncJavaScript(
                """
                const api = globalThis.SatchelCapture;
                if (!api) throw new Error('the capture engine did not load');
                for (const holder of document.querySelectorAll('textarea[data-satchel-ld]')) {
                  const script = document.createElement('script');
                  script.type = 'application/ld+json';
                  script.textContent = holder.value;
                  holder.replaceWith(script);
                }
                return JSON.stringify(api.captureLink(document, { pageUrl: location.href }).metadata);
                """, arguments: [:], in: nil, contentWorld: .defaultClient)
        } catch {
            throw EnrichmentError.capture(String(describing: error))
        }
        guard let string = json as? String,
            let metadata = try? JSONDecoder().decode(LinkMetadata.self, from: Data(string.utf8))
        else { throw EnrichmentError.capture("captureLink returned nothing usable") }
        return metadata
    }

    /// Blocks every load except the document itself.
    private func blockingRules() async throws -> WKContentRuleList? {
        if let ruleList { return ruleList }
        let rules = """
            [{"trigger": {"url-filter": ".*", "resource-type": ["image", "style-sheet", "script", "font", "raw",
              "svg-document", "media", "popup", "ping", "fetch", "websocket", "other"]},
              "action": {"type": "block"}}]
            """
        let list = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "satchel-enrichment", encodedContentRuleList: rules)
        ruleList = list
        return list
    }

    /// One navigation's outcome, delivered once.
    private final class Navigation: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, any Error>?

        func wait(_ start: () -> Void) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                start()
            }
        }

        func cancel() { finish(.failure(CancellationError())) }

        private func finish(_ result: Result<Void, any Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(.success(())) }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            finish(.failure(EnrichmentError.load(error.localizedDescription)))
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
        ) {
            finish(.failure(EnrichmentError.load(error.localizedDescription)))
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
            decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
        ) {
            // Only HTML documents: a shared link to a PDF or an image has nothing for captureLink.
            let type = response.response.mimeType ?? "text/html"
            if response.isForMainFrame, !["text/html", "application/xhtml+xml"].contains(type) {
                decisionHandler(.cancel)
                finish(.failure(EnrichmentError.load("not an HTML page (\(type))")))
                return
            }
            decisionHandler(.allow)
        }
    }
}
