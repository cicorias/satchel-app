import SatchelKit
import SwiftUI

/// Phase 3 ticket 06: the saved items, newest first, with their sync state. Search, filters, and the detail view
/// arrive in ticket 10 (spec §9.2.4).
struct LibraryView: View {
    @State private var model = LibraryModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.error {
                    ContentUnavailableView(
                        "Library unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if model.items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing saved yet", systemImage: "bookmark")
                    } description: {
                        Text("Share a link from any app to save it here.")
                    }
                } else {
                    List(model.items) { item in
                        ItemRow(item: item, state: model.unsent[item.id])
                    }
                    .accessibilityIdentifier("library-list")
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        .task { await model.observe() }
    }
}

private struct ItemRow: View {
    let item: Item
    let state: OutboxState?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.headline).lineLimit(2)
            HStack(spacing: 6) {
                Text(item.siteName ?? URL(string: item.url)?.host() ?? item.url)
                if item.metadataStatus == .pending { Text("· details pending") }
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("item-\(item.id)")
    }
}

#Preview {
    LibraryView()
}
