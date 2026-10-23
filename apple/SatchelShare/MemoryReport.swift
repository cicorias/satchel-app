#if DEBUG
    import Darwin
    import Foundation
    import SatchelKit

    /// Debug builds only (ticket 09): appends this process's memory footprint after a Safari capture arrives to
    /// `<App Group>/Library/share-memory.jsonl`, which `devicectl device copy from` can read off a device. Share
    /// extensions run under tight memory limits, so this measures a large page.
    enum MemoryReport {
        static func record(url: String, bodyBytes: Int) {
            guard let environment = try? AppEnvironment.current(),
                let container = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: environment.appGroup)
            else { return }
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            guard status == KERN_SUCCESS else { return }
            let entry: [String: Any] = [
                "url": url, "bodyBytes": bodyBytes, "footprintBytes": info.phys_footprint,
                "peakBytes": info.ledger_phys_footprint_peak, "limitRemainingBytes": os_proc_available_memory(),
                "at": ItemSaver.timestamp(Date()),
            ]
            guard var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
            line.append(0x0A)
            let file = container.appending(path: "Library/share-memory.jsonl")
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(line)
                try? handle.close()
            } else {
                try? line.write(to: file)
            }
        }
    }
#endif
