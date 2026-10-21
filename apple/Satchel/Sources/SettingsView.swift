import SatchelKit
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    private let environment = try? AppEnvironment.current()

    var body: some View {
        NavigationStack {
            Form {
                Section("Storage") {
                    LabeledContent("Provider", value: "iCloud")
                    LabeledContent("Container", value: environment?.iCloudContainer ?? "—")
                }
                Section("About") {
                    LabeledContent("Version", value: environment.map { "\($0.version) (\($0.build))" } ?? "—")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
