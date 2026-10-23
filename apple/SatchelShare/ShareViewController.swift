import SatchelKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point (spec §9.2.2). A URL shared from any app is saved as a link waiting for enrichment.
/// Page capture from Safari (the preprocessing script) arrives in ticket 09.
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
        case saved(synced: Bool)
        case failed(String)
    }

    private(set) var phase = Phase.loading
    private(set) var url: String?
    private(set) var title: String?

    func load(_ items: [NSExtensionItem]) async {
        if let shared = await SharedURL.find(in: items) {
            url = shared.url
            title = shared.title
            phase = .ready
        } else {
            phase = .failed("There's no web link to save here.")
        }
    }

    func save() async {
        guard let url else { return }
        phase = .saving
        do {
            Store.resume()
            let saver = try ItemSaver.standard()
            let outcome = try await saver.saveLink(url: url, title: title, client: .iosShare)
            if case .saved = outcome.cloud {
                phase = .saved(synced: true)
            } else {
                phase = .saved(synced: false)
            }
        } catch SatchelModelError.unsupportedURL {
            phase = .failed("Only web links (http and https) can be saved.")
        } catch {
            phase = .failed("Couldn't save: \(error.localizedDescription)")
        }
    }
}

/// The first web URL in what the host app shared: a URL item, or text that contains one.
@MainActor
enum SharedURL {
    static func find(in items: [NSExtensionItem]) async -> (url: String, title: String?)? {
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
    let model: ShareModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch model.phase {
                case .loading:
                    ProgressView()
                case .ready, .saving:
                    VStack(alignment: .leading, spacing: 6) {
                        if let title = model.title { Text(title).font(.headline).lineLimit(2) }
                        Text(model.url ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        Task { await model.save() }
                    } label: {
                        Text(model.phase == .saving ? "Saving…" : "Save link").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.phase == .saving)
                    .accessibilityIdentifier("save-link")
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
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Save to Satchel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
            }
        }
    }
}
