# Ticket 01 probe (reference copy)

The temporary host-app benchmark used on 2026-10-22 for ADR-0020. It is kept here, not compiled, so it can be re-run. To use it:

1. Save the Swift below in `apple/Satchel/Probe/`.
2. Copy `packages/model/dist/model.jsc.iife.js` next to it.
3. In `SatchelApp.init`, call `ModelBenchmark.run()` when `SATCHEL_MODEL_BENCHMARK=1`.
4. Build signed (`FORCE=1 SIGNED=1 DESTINATION=… mise run build:ios`), and install with `devicectl`.
5. Launch on an **unlocked** phone with `xcrun devicectl device process launch --device <UDID> --terminate-existing --environment-variables '{"SATCHEL_MODEL_BENCHMARK":"1"}' com.cedarlogic.satchel`.
6. Pull `Library/model-benchmark.json` from the App Group container with `devicectl device copy from`.

```swift
// TEMPORARY: Phase 3 ticket 01 probe. Removed when the ticket resolves.
import Foundation
import JavaScriptCore

enum ModelBenchmark {
    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func run() {
        let url = Bundle.main.url(forResource: "model.jsc.iife", withExtension: "js")!
        let before = footprint()
        let t0 = Date()
        let source = try! String(contentsOf: url, encoding: .utf8)
        let context = JSContext()!
        var error = ""
        context.exceptionHandler = { _, e in error = e?.toString() ?? "?" }
        context.evaluateScript(source)
        let t1 = Date()
        let first = context.evaluateScript(
            "SatchelModel.itemIdFor(SatchelModel.normalizedUrlFor('https://www.example.com/articles/hello-world/?utm_source=newsletter#comments', 'https://example.com/articles/hello-world'))"
        )!.toString()!
        let t2 = Date()
        for i in 0..<1000 {
            _ = context.evaluateScript("SatchelModel.itemIdFor(SatchelModel.normalizedUrlFor('https://news.example.co.uk/a/\(i)?utm_source=x&b=2&a=1'))")
        }
        let t3 = Date()
        let after = footprint()
        let report: [String: Any] = [
            "loadMs": t1.timeIntervalSince(t0) * 1000,
            "firstCallMs": t2.timeIntervalSince(t1) * 1000,
            "perCallMs": t3.timeIntervalSince(t2),
            "footprintBeforeMB": Double(before) / 1_048_576,
            "footprintAfterMB": Double(after) / 1_048_576,
            "firstId": first,
            "error": error,
            "date": ISO8601DateFormatter().string(from: Date()),
        ]
        let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.cedarlogic.satchel")!
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try! data.write(to: dir.appendingPathComponent("Library/model-benchmark.json"))
    }
}
```
