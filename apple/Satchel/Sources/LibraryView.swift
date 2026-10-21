import SwiftUI

/// Phase 3: list, search (FTS5), tag/kind filters, detail view (spec §9.2.4).
struct LibraryView: View {
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Nothing saved yet", systemImage: "bookmark")
            } description: {
                Text("Share a page from Safari, or use the Satchel extension, to save it here.")
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
    }
}

#Preview {
    LibraryView()
}
