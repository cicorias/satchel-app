import Foundation
import Network
import Synchronization

/// `NetworkConditions` from the system's current path: no enrichment while offline, or on cellular with Low Data
/// Mode on (spec §9.2.4).
public final class NetworkPath: NetworkConditions {
    private let monitor = NWPathMonitor()
    private let path = Mutex<NWPath?>(nil)

    public init() {
        monitor.pathUpdateHandler = { [weak self] update in self?.path.withLock { $0 = update } }
        monitor.start(queue: DispatchQueue(label: "com.cedarlogic.satchel.network-path"))
    }

    deinit { monitor.cancel() }

    public var allowsEnrichment: Bool {
        get async {
            guard let current = path.withLock({ $0 }) else { return true }
            guard current.status == .satisfied else { return false }
            return !(current.isConstrained && current.usesInterfaceType(.cellular))
        }
    }
}
