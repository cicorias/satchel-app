import SatchelKit
import SwiftUI

/// The library (FR-7, spec §9.2.4): saved items, newest first, with search (FTS5 over title, description, site, tags,
/// and body), filters by kind and tag, and each item's sync state (FR-8). Swipe to delete, pull to sync, tap for the
/// detail view.
struct LibraryView: View {
    @State private var model = LibraryModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.error {
                    ContentUnavailableView(
                        "Library unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if model.items.isEmpty && model.query == .init() {
                    ContentUnavailableView {
                        Label("Nothing saved yet", systemImage: "bookmark")
                    } description: {
                        Text("Share a link from any app to save it here.")
                    }
                } else if model.items.isEmpty {
                    ContentUnavailableView.search(text: model.query.text)
                } else {
                    list
                }
            }
            .navigationTitle("Library")
            .searchable(text: $model.query.text, prompt: "Search titles, tags, and text")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let item = model.items.first(where: { $0.id == id }) {
                    ItemDetailView(item: item, state: model.unsent[id], library: model)
                } else {
                    ContentUnavailableView("Item not found", systemImage: "questionmark")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(model: model)
            }
            .fullScreenCover(isPresented: $model.showingOnboarding) {
                OnboardingView(status: model.syncStatus) { model.finishOnboarding() }
            }
        }
        .task { await model.observe() }
        .task(id: model.query) { await model.observeItems() }
    }

    private var list: some View {
        List {
            ForEach(model.items) { item in
                NavigationLink(value: item.id) {
                    ItemRow(item: item, state: model.unsent[item.id], showsImage: model.loadsRemoteImages)
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { model.items[$0] }
                Task { for item in doomed { await model.delete(item) } }
            }
            if !model.syncStatus.isHealthy {
                Label(model.syncStatus.explanation.text, systemImage: model.syncStatus.explanation.symbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sync-status")
            }
        }
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("library-list")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Kind", selection: $model.query.kind) {
                ForEach(LibraryModel.KindFilter.allCases) { Text($0.title).tag($0) }
            }
            if !model.tags.isEmpty {
                Picker("Tag", selection: $model.query.tag) {
                    Text("Any tag").tag(String?.none)
                    ForEach(model.tags, id: \.self) { Text($0).tag(Optional($0)) }
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: model.query.isFiltered
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("filter")
    }
}

private struct ItemRow: View {
    let item: Item
    let state: OutboxState?
    /// Remote images are on (spec §11), so the item's preview image may be fetched from its site.
    let showsImage: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            details
            Spacer(minLength: 0)
            if showsImage, let url = item.imageURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("item-\(item.id)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline).lineLimit(2)
            HStack(spacing: 6) {
                Text(item.siteName ?? URL(string: item.url)?.host() ?? item.url)
                if let page = item.page { Text("· page, \(page.readingMinutes) min") }
                if item.metadataStatus == .pending { Text("· details pending") }
                if item.metadataStatus == .failed { Text("· details unavailable") }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let state {
                Label(
                    state == .failed ? "Not synced yet" : "Waiting to sync",
                    systemImage: state == .failed ? "icloud.slash" : "icloud.and.arrow.up"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }
}

#Preview {
    LibraryView()
}
