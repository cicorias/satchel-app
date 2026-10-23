import SatchelKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point (spec §9.2.2). From Safari, the preprocessing script (`preprocessing.js`) has already
/// captured the page, so the sheet offers Save link and Save page. From any other app, a shared URL is saved as a link
/// waiting for enrichment. Both take tags and a note (FR-5).
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareSheet(model: model) { [weak self] in self?.finish() })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.load(items) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Store.suspend()
    }

    private func finish() {
        Store.suspend()
        extensionContext?.completeRequest(returningItems: nil)
    }
}

@MainActor @Observable
final class ShareModel {
    enum Phase: Equatable {
        case loading
        case ready
        case saving
        /// A page is already saved for this URL: "Replace saved copy?"
        case confirmReplace
        case saved(synced: Bool)
        case failed(String)
    }

    private(set) var phase = Phase.loading
    private(set) var url: String?
    private(set) var title: String?
    /// The page capture from Safari, if it worked.
    private(set) var page: SafariShareCapture.Captured?
    /// Why Save page isn't offered, when Safari tried.
    private(set) var pageUnavailable: String?
    private(set) var knownTags: [String] = []
    /// A recoverable problem shown under the buttons (the sheet stays usable).
    private(set) var message: String?
    var tagText = ""
    var note = ""

    private var link: SafariShareCapture.Captured?
    private var saver: ItemSaver?

    var suggestions: [String] { TagInput.suggestions(for: tagText, from: knownTags) }

    func load(_ items: [NSExtensionItem]) async {
        if let capture = await SharedContent.safariCapture(in: items) {
            url = capture.url
            title = capture.link?.item.title ?? capture.title
            link = capture.link
            page = capture.page
            pageUnavailable = capture.page == nil ? capture.pageError : nil
            #if DEBUG
                MemoryReport.record(url: capture.url, bodyBytes: capture.page?.body?.utf8.count ?? 0)
            #endif
        } else if let shared = await SharedContent.url(in: items) {
            url = shared.url
            title = shared.title
        } else {
            phase = .failed("There's no web link to save here.")
            return
        }
        phase = .ready
        Store.resume()
        do {
            let saver = try ItemSaver.standard()
            self.saver = saver
            knownTags = try await saver.store.tags(limit: 50)
        } catch {
            phase = .failed("Satchel's library couldn't be opened: \(error)")
        }
    }

    func complete(with tag: String) {
        tagText = TagInput.completing(tagText, with: tag)
    }

    func saveLink() async {
        guard let saver, let url else { return }
        await save {
            let tags = TagInput.tags(from: self.tagText)
            if let link = self.link {
                return try await saver.saveCapture(link.item.adding(tags: tags, note: self.note), body: nil)
            }
            return .saved(
                try await saver.saveLink(url: url, title: self.title, tags: tags, note: self.note, client: .iosShare))
        }
    }

    func savePage(_ existingPage: ItemSaver.ExistingPage = .ask) async {
        guard let saver, let page else { return }
        await save {
            let item = page.item.adding(tags: TagInput.tags(from: self.tagText), note: self.note)
            return try await saver.saveCapture(item, body: page.body, existingPage: existingPage)
        }
    }

    private func save(_ operation: () async throws -> ItemSaver.CaptureSave) async {
        phase = .saving
        message = nil
        Store.resume()
        do {
            switch try await operation() {
            case .confirmReplace:
                phase = .confirmReplace
            case .saved(let outcome):
                if case .saved = outcome.cloud { phase = .saved(synced: true) } else { phase = .saved(synced: false) }
            }
        } catch let problem as ItemSaver.CaptureProblem {
            phase = .ready
            message = problem.description
        } catch SatchelModelError.unsupportedURL(_) {
            phase = .failed("Only web links (http and https) can be saved.")
        } catch {
            phase = .ready
            message = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// What the host app shared.
@MainActor
enum SharedContent {
    /// Safari's preprocessing result, when the share came from Safari.
    static func safariCapture(in items: [NSExtensionItem]) async -> SafariShareCapture? {
        for item in items {
            for provider in item.attachments ?? []
            where provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                guard
                    let dictionary = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier)
                        as? [String: Any],
                    let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                else { continue }
                if let capture = SafariShareCapture.decode(results: results) { return capture }
            }
        }
        return nil
    }

    /// The first web URL in what the host app shared: a URL item, or text that contains one.
    static func url(in items: [NSExtensionItem]) async -> (url: String, title: String?)? {
        for item in items {
            let title = item.attributedContentText?.string ?? item.attributedTitle?.string
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                    let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
                    isWeb(url)
                {
                    return (url.absoluteString, title.flatMap { $0 == url.absoluteString ? nil : $0 })
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                    let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                    let url = firstWebURL(in: text)
                {
                    return (url.absoluteString, nil)
                }
            }
        }
        return nil
    }

    static func firstWebURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range).compactMap(\.url).first(where: isWeb)
    }

    private static func isWeb(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https"
    }
}

private struct ShareSheet: View {
    @Bindable var model: ShareModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView()
                case .saved(let synced):
                    Label(synced ? "Saved" : "Saved — will sync later", systemImage: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("saved")
                        .task {
                            try? await Task.sleep(for: .milliseconds(700))
                            onDone()
                        }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                case .ready, .saving, .confirmReplace:
                    form
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding()
            .navigationTitle("Save to Satchel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
            }
            .confirmationDialog(
                "This page is already saved. Replace saved copy?",
                isPresented: .init(get: { model.phase == .confirmReplace }, set: { _ in }), titleVisibility: .visible
            ) {
                Button("Replace") { Task { await model.savePage(.replace) } }
                Button("Keep saved copy") { Task { await model.savePage(.keep) } }
                Button("Cancel", role: .cancel) { onDone() }
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    if let title = model.title { Text(title).font(.headline).lineLimit(2) }
                    Text(model.url ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Tags, separated by commas or periods", text: $model.tagText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("tags")
                    if !model.suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(model.suggestions, id: \.self) { tag in
                                    Button(tag) { model.complete(with: tag) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    TextField("Note", text: $model.note, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("note")
                }
                Button {
                    Task { await model.saveLink() }
                } label: {
                    Text(model.phase == .saving ? "Saving…" : "Save link").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("save-link")
                if model.page != nil {
                    Button {
                        Task { await model.savePage() }
                    } label: {
                        Text("Save page").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("save-page")
                } else if let reason = model.pageUnavailable {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
                if let message = model.message {
                    Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
            }
            .disabled(model.phase == .saving)
        }
    }
}
