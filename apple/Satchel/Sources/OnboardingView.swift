import SatchelKit
import SwiftUI

/// The first-run page (spec §9.2.4): how to save from Safari and from other apps, and where iCloud stands. Also
/// opened from Settings → How to Save.
struct OnboardingView: View {
    let status: SyncStatus
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Satchel").font(.largeTitle.bold())
                        Text("Save links and whole pages as Markdown, kept in your own iCloud.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Step(title: "Turn on the Safari extension", symbol: "safari") {
                        Numbered(1, "Open the **Settings** app, then **Apps → Safari → Extensions → Satchel**.")
                        Numbered(2, "Turn on **Allow Extension**.")
                        Numbered(3, "Under Permissions, allow **All Websites**, or answer when Safari asks.")
                        Numbered(4, "In Safari, tap the page menu in the address bar, then **Satchel**.")
                    }

                    Step(title: "Share from any app", symbol: "square.and.arrow.up") {
                        Text(
                            "Tap **Share**, then **Satchel**. If it isn't in the row of apps, tap **More** and add it.")
                        Text(
                            "From Safari you can save the whole page. From other apps, Satchel saves the link and fills in its title and image."
                        )
                        .foregroundStyle(.secondary)
                    }

                    Step(title: "iCloud", symbol: status.explanation.symbol) {
                        Text(status.explanation.text)
                        Text(
                            "Saves always work, even offline. They're kept on this iPhone and sync when iCloud is available."
                        )
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("onboarding-icloud")
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onDone) {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .accessibilityIdentifier("onboarding-done")
            }
        }
    }
}

private struct Step<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            VStack(alignment: .leading, spacing: 8) { content }
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct Numbered: View {
    let number: Int
    let text: LocalizedStringKey

    init(_ number: Int, _ text: LocalizedStringKey) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").font(.subheadline.bold()).foregroundStyle(.secondary).frame(width: 16)
            Text(text)
        }
    }
}
