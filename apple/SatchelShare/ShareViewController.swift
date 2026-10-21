import SwiftUI
import UIKit

/// Share Extension entry point (spec §9.2.2). Phase 3: link/page save sheet, outbox write, one-shot CloudKit save.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareSheet { [weak self] in self?.finish() })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct ShareSheet: View {
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Saving arrives in Phase 3", systemImage: "bookmark")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onDone)
                    }
                }
        }
    }
}
