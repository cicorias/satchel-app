import SatchelKit
import SwiftUI

/// Settings (spec §9.2.4, §11): iCloud status, "Load remote images", help and policy links, and the version.
struct SettingsView: View {
    @Bindable var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingHelp = false
    @State private var confirmingStartOver = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Storage", value: "iCloud")
                    Label(model.syncStatus.explanation.text, systemImage: model.syncStatus.explanation.symbol)
                        .accessibilityIdentifier("settings-sync-status")
                    if model.syncStatus == .otherAccount {
                        Button("Use This iCloud Account…", role: .destructive) { confirmingStartOver = true }
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("Your library is stored in your private iCloud database. CedarLogic can't see it.")
                }

                Section {
                    Toggle("Load Remote Images", isOn: $model.loadsRemoteImages)
                        .accessibilityIdentifier("remote-images")
                } header: {
                    Text("Reading")
                } footer: {
                    Text(
                        "Saved pages and link previews show their images from the original websites, which can see that you loaded them. When this is off, tap Load Images on a page to load them once."
                    )
                }

                Section("Help") {
                    Button("How to Save") { showingHelp = true }
                    if let site = model.siteURL {
                        Link("Privacy Policy", destination: site.appending(path: "privacy.html"))
                        Link("Support", destination: site.appending(path: "support.html"))
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: model.version)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Erase this iPhone's library and sync with the iCloud account now signed in?",
                isPresented: $confirmingStartOver, titleVisibility: .visible
            ) {
                Button("Erase and Sync", role: .destructive) { Task { await model.startOver() } }
            } message: {
                Text(
                    "Items saved under the other account stay in that account's iCloud. Unsynced saves on this iPhone are lost."
                )
            }
            .sheet(isPresented: $showingHelp) {
                OnboardingView(status: model.syncStatus) { showingHelp = false }
            }
        }
    }
}
