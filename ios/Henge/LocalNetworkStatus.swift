import Foundation
import Network
import Observation

/// The iPad's connection, not a claim that the guest has a Wi-Fi radio.
@MainActor @Observable final class LocalNetworkStatus {
    private(set) var connection = "Checking…"
    @ObservationIgnored private var monitor: NWPathMonitor?
    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let label = path.status != .satisfied ? "Offline"
                : path.usesInterfaceType(.wifi) ? "Wi-Fi"
                : path.usesInterfaceType(.wiredEthernet) ? "Ethernet"
                : path.usesInterfaceType(.cellular) ? "Cellular" : "Connected"
            Task { @MainActor [weak self] in self?.connection = label }
        }
        monitor.start(queue: DispatchQueue(label: "henge.network.status"))
    }
    func stop() { monitor?.cancel(); monitor = nil }
    deinit { monitor?.cancel() }
}
