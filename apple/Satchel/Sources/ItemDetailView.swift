import SatchelKit
import SwiftUI
import UIKit

/// One saved item (FR-7): a page's rendered Markdown, or a link's description, with copy, export, open, and delete.
struct ItemDetailView: View {
    let item: Item
    let state: OutboxState?
    let library: LibraryModel

    @Environment(\.dismiss) private var dismiss
    @State private var body_: String?
    @State private var exportFile: URL?
    @State private var markdown: String?
    @State private var loadImages = false
    @State private var report = MarkdownWebView.Report()
    @State private var confirmingDelete = false
    @State private var copied = false

    var body: some View {
        content
            .navigationTitle(item.siteName ?? URL(string: item.url)?.host() ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { banner }
            .confirmationDialog("Delete this item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await library.delete(item)
                        dismiss()
                    }
                }
            } message: {
                Text("It's removed from this iPhone and from iCloud.")
            }
            .task(id: item) { await prepare() }
    }

    @ViewBuilder private var content: some View {
        if item.kind == .page, let body_ {
            MarkdownWebView(
                header: header, markdown: body_, remoteImages: loadImages || library.loadsRemoteImages
            ) { report = $0 }
            .ignoresSafeArea(edges: .bottom)
            #if DEBUG
                .overlay(alignment: .topLeading) {
                    // For UI tests: what the rendered page contains (spec §11 checks).
                    Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("render-report")
                    .accessibilityValue(report.summary)
                }
            #endif
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title).font(.title.bold())
                    Text(header.byline).font(.subheadline).foregroundStyle(.secondary)
                    if !item.tags.isEmpty {
                        Text(item.tags.joined(separator: ", ")).font(.subheadline)
                    }
                    if let note = item.note { Text(note).italic() }
                    Divider()
                    if let description = item.description {
                        Text(description)
                    }
                    Text(
                        item.kind == .page
                            ? "The saved copy isn't on this iPhone yet."
                            : "This is a link. Share the page from Safari to save a copy."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let exportFile {
                ShareLink(item: exportFile) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("export")
            }
            Menu {
                if let url = URL(string: item.url) {
                    Link(destination: url) { Label("Open in Safari", systemImage: "safari") }
                }
                Button("Copy Markdown", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = markdown
                    copied = true
                }
                .disabled(markdown == nil)
                if report.blockedImages > 0 && !loadImages {
                    Button("Load Images (\(report.blockedImages))", systemImage: "photo") { loadImages = true }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("item-actions")
        }
    }

    @ViewBuilder private var banner: some View {
        if copied {
            Label("Markdown copied", systemImage: "checkmark.circle.fill")
                .padding(10)
                .background(.thinMaterial, in: Capsule())
                .task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
        } else if let state {
            Label(
                state == .failed ? "Not synced yet" : "Waiting to sync",
                systemImage: state == .failed ? "icloud.slash" : "icloud.and.arrow.up"
            )
            .font(.footnote)
            .padding(8)
            .background(.thinMaterial, in: Capsule())
        }
    }

    private var header: MarkdownWebView.Header {
        var parts = [item.siteName ?? URL(string: item.url)?.host() ?? item.url]
        if let author = item.author { parts.append(author) }
        if let date = Self.date(item.createdAt) {
            parts.append("Saved \(date.formatted(date: .abbreviated, time: .omitted))")
        }
        if let page = item.page { parts.append("\(page.readingMinutes) min read") }
        return MarkdownWebView.Header(
            title: item.title, byline: parts.joined(separator: " · "), tags: item.tags, note: item.note)
    }

    private func prepare() async {
        body_ = await library.body(for: item)
        markdown = library.markdownFile(for: item, body: body_)
        exportFile = markdown.flatMap { library.exportFile(for: item, markdown: $0) }
    }

    private static func date(_ iso: String) -> Date? {
        (try? Date(iso, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(iso, strategy: .iso8601))
    }
}
