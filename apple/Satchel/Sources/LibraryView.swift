import SatchelKit
import SwiftUI

/// The saved items, newest first, with their sync state; swipe to delete, pull to sync. Search, filters, and the
/// detail view arrive in ticket 10, and the full sync status in settings in ticket 12 (spec §9.2.4).
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
                    List {
                        ForEach(model.items) { item in
                            ItemRow(item: item, state: model.unsent[item.id])
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { model.items[$0] }
                            Task { for item in doomed { await model.delete(item) } }
                        }
                        if let note = SyncNote(model.syncStatus) {
                            Label(note.text, systemImage: note.symbol)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("sync-status")
                        }
                    }
                    .refreshable { await model.refresh() }
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

/// A one-line explanation when sync isn't working normally.
private struct SyncNote {
    let text: String
    let symbol: String

    init?(_ status: SyncStatus) {
        switch status {
        case .starting, .syncing, .upToDate:
            return nil
        case .noAccount:
            (text, symbol) = ("Sign in to iCloud to sync. Saves are kept on this iPhone until then.", "icloud.slash")
        case .temporarilyUnavailable:
            (text, symbol) = ("iCloud isn't available right now. Saves will sync later.", "icloud.slash")
        case .otherAccount:
            (text, symbol) = (
                "This library belongs to a different iCloud account, so sync is paused.",
                "person.crop.circle.badge.exclamationmark"
            )
        case .failed(let reason):
            (text, symbol) = ("Sync stopped: \(reason)", "exclamationmark.icloud")
        }
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
                if let page = item.page { Text("· page, \(page.readingMinutes) min") }
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
