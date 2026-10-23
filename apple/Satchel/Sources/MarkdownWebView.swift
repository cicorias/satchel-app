import SwiftUI
import UIKit
import WebKit

/// Renders a saved page's Markdown with `render.iife.js` (`@satchel/render`) in a `WKWebView`, so pages look the same
/// as in the browser library (spec §9.1.4, §11).
///
/// - **No page scripts:** content JavaScript is off (`allowsContentJavaScript = false`). The renderer runs in the
///   `.defaultClient` content world, which the page can't reach, and its output is sanitized by DOMPurify.
/// - **No remote content** unless `remoteImages` is on: the page's CSP is `default-src 'none'` (inline styles and
///   `data:` images only), and the renderer swaps remote images for placeholders.
/// - **No navigation:** a tapped link opens in Safari; only in-page `#` links move within the view.
struct MarkdownWebView: UIViewRepresentable {
    struct Header: Equatable {
        var title: String
        var byline: String
        var tags: [String]
        var note: String?
    }

    /// What the rendered document contains, from inside the web view. UI tests read it in Debug builds.
    struct Report: Equatable {
        var blockedImages = 0
        var scripts = 0
        var handlers = 0
        var resources = 0
        var violations = 0

        var summary: String {
            "scripts \(scripts), handlers \(handlers), resources \(resources), violations \(violations), blocked \(blockedImages)"
        }
    }

    let header: Header
    let markdown: String
    let remoteImages: Bool
    var onReport: (Report) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.dataDetectorTypes = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.accessibilityIdentifier = "markdown-view"
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        let document = Coordinator.Document(header: header, markdown: markdown, remoteImages: remoteImages)
        guard context.coordinator.document != document else { return }
        context.coordinator.document = document
        context.coordinator.onReport = onReport
        view.loadHTMLString(Self.shell(remoteImages: remoteImages), baseURL: nil)
    }

    /// The empty document the renderer fills in. Remote images are allowed by the CSP only when they're on.
    static func shell(remoteImages: Bool) -> String {
        let images = remoteImages ? "data: https: http:" : "data:"
        return """
            <!doctype html><html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src \(images)">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>\(css)</style></head>
            <body><header id="header"></header><article id="content"></article></body></html>
            """
    }

    static let css = """
        :root { color-scheme: light dark; --muted: #6b6b70; --rule: #d9d9de; --code: #f2f2f5; }
        @media (prefers-color-scheme: dark) { :root { --muted: #a1a1a8; --rule: #3a3a3f; --code: #1c1c1f; } }
        body { font: -apple-system-body; margin: 0; padding: 16px 16px 48px; line-height: 1.55; overflow-wrap: break-word; }
        header h1 { font: -apple-system-title1; font-weight: 700; margin: 0 0 6px; }
        header p { color: var(--muted); margin: 0 0 4px; font-size: 0.9em; }
        header .tags span { display: inline-block; border: 1px solid var(--rule); border-radius: 999px; padding: 0 8px; margin: 0 4px 4px 0; font-size: 0.85em; }
        header .note { font-style: italic; }
        header { border-bottom: 1px solid var(--rule); padding-bottom: 12px; margin-bottom: 16px; }
        img { max-width: 100%; height: auto; }
        pre { background: var(--code); padding: 10px 12px; border-radius: 8px; overflow-x: auto; }
        code { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
        :not(pre) > code { background: var(--code); padding: 1px 4px; border-radius: 4px; }
        blockquote { margin: 0; padding-left: 12px; border-left: 3px solid var(--rule); color: var(--muted); }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        th, td { border: 1px solid var(--rule); padding: 4px 8px; }
        a { color: -apple-system-blue; }
        .image-blocked, .image-missing { display: inline-block; border: 1px dashed var(--rule); border-radius: 6px; padding: 6px 10px; color: var(--muted); font-size: 0.9em; }
        .image-blocked::before { content: "Image not loaded: "; }
        """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        struct Document: Equatable {
            var header: Header
            var markdown: String
            var remoteImages: Bool
        }

        var document: Document?
        var onReport: (Report) -> Void = { _ in }

        /// `render.iife.js` from the app bundle, loaded once.
        static let renderer: String? = Bundle.main.url(forResource: "render.iife", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let document, let renderer = Self.renderer else { return }
            let arguments: [String: Any] = [
                "markdown": document.markdown, "remoteImages": document.remoteImages,
                "title": document.header.title, "byline": document.header.byline, "tags": document.header.tags,
                "note": document.header.note ?? "",
            ]
            Task {
                // The renderer defines globalThis.SatchelRender in this world on first use.
                _ = try? await webView.callAsyncJavaScript(
                    renderer, arguments: [:], in: nil, contentWorld: .defaultClient)
                let result = try? await webView.callAsyncJavaScript(
                    Self.renderScript, arguments: arguments, in: nil, contentWorld: .defaultClient)
                guard let values = result as? [String: Any] else { return }
                func count(_ key: String) -> Int { (values[key] as? NSNumber)?.intValue ?? 0 }
                // Remote loads would start after insertion; look again once they've had a moment.
                try? await Task.sleep(for: .milliseconds(500))
                let later =
                    try? await webView.callAsyncJavaScript(
                        Self.countScript, arguments: [:], in: nil, contentWorld: .defaultClient) as? [String: Any]
                func laterCount(_ key: String) -> Int { (later?[key] as? NSNumber)?.intValue ?? count(key) }
                onReport(
                    Report(
                        blockedImages: count("blocked"), scripts: laterCount("scripts"),
                        handlers: laterCount("handlers"), resources: laterCount("resources"),
                        violations: laterCount("violations")))
            }
        }

        /// Fills in the header with text nodes (never HTML), renders the body, and counts what the page holds.
        static let renderScript = """
            const header = document.getElementById('header');
            const add = (tag, text, cls) => {
              const el = document.createElement(tag);
              el.textContent = text;
              if (cls) el.className = cls;
              header.appendChild(el);
              return el;
            };
            add('h1', title);
            if (byline) add('p', byline);
            if (tags.length) {
              const row = add('p', '', 'tags');
              for (const tag of tags) row.appendChild(Object.assign(document.createElement('span'), { textContent: tag }));
            }
            if (note) add('p', note, 'note');
            globalThis.__violations = 0;
            document.addEventListener('securitypolicyviolation', () => { globalThis.__violations += 1; });
            const result = SatchelRender.render(markdown, { remoteImages, linkTarget: null });
            const content = document.getElementById('content');
            content.innerHTML = result.html;
            // A page body starts with "# title"; the header already shows it.
            const first = content.firstElementChild;
            if (first?.tagName === 'H1' && first.textContent.trim() === title.trim()) first.remove();
            return { blocked: result.blockedImages, ...(\(countBody)) };
            """

        static let countScript = "return \(countBody);"

        private static let countBody = """
            {
              scripts: document.scripts.length,
              handlers: [...document.querySelectorAll('*')].filter((el) => [...el.attributes].some((a) => a.name.startsWith('on'))).length,
              resources: performance.getEntriesByType('resource').length,
              violations: globalThis.__violations || 0,
            }
            """

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            // The shell itself (loaded with no base URL), and jumps to footnotes within it.
            if url.scheme == "about" { return decisionHandler(.allow) }
            if action.navigationType == .linkActivated, ["http", "https", "mailto"].contains(url.scheme?.lowercased()) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
