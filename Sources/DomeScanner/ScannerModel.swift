import EasyIPKit
import Foundation
import Observation

enum ReachStatus: Equatable {
    case reachable(NetworkInterface)
    case otherSubnet
    case duplicateIP

    var label: String {
        switch self {
        case let .reachable(interface): "Reachable via \(interface.displayName) (\(interface.bsdName))"
        case .otherSubnet: "Other subnet: not reachable from this Mac until its IP is changed"
        case .duplicateIP: "Duplicate IP: another camera uses the same address"
        }
    }
}

@MainActor @Observable
final class ScannerModel {
    private(set) var cameras: [Camera] = []
    private(set) var interfaces: [NetworkInterface] = []
    private(set) var isSearching = false
    var errorMessage: String?

    private var client: EasyIPClient?
    private var searchGeneration = 0

    func start() {
        guard client == nil else { return }
        do {
            let client = try EasyIPClient()
            client.onCamera = { [weak self] camera in self?.add(camera) }
            self.client = client
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        Task { await search() }
    }

    /// Clears the list and searches on every interface.
    func search() async {
        guard let client else { return start() }
        searchGeneration += 1
        let generation = searchGeneration
        cameras.removeAll()
        interfaces = client.refreshInterfaces()
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            try await client.search()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cameras restart their network stack after a change; search again once they are back.
    func searchAgain(after delay: Duration = .seconds(3)) {
        Task {
            try? await Task.sleep(for: delay)
            await search()
        }
    }

    func apply(_ settings: NetworkSettings, to camera: Camera) async throws {
        guard let client else { throw ReconfigureError.noInterfaces }
        try await client.reconfigure(camera, to: settings)
        interfaces = client.interfaces
        cameras.removeAll { $0.mac == camera.mac }
    }

    private func add(_ camera: Camera) {
        if let index = cameras.firstIndex(where: { $0.mac == camera.mac }) {
            cameras[index] = camera
        } else {
            cameras.append(camera)
        }
    }

    // MARK: Derived info

    func status(of camera: Camera) -> ReachStatus {
        if cameras.contains(where: { $0.mac != camera.mac && $0.ipv4 == camera.ipv4 }) {
            return .duplicateIP
        }
        if let interface = interfaces.first(where: { $0.contains(camera.ipv4) }) {
            return .reachable(interface)
        }
        return .otherSubnet
    }

    /// Addresses already in use by this Mac or by discovered cameras (except `excluding`).
    func addressesInUse(excluding: Set<MACAddress> = []) -> Set<IPv4> {
        Set(interfaces.map(\.ipv4)).union(cameras.filter { !excluding.contains($0.mac) }.map(\.ipv4))
    }

    /// A free address for `camera` inside `interface`'s subnet, keeping its host part if possible.
    func suggestedAddress(for camera: Camera, in interface: NetworkInterface) -> IPv4 {
        let mask = interface.netmask.value
        let network = interface.ipv4.value & mask
        let broadcast = network | ~mask
        let used = addressesInUse(excluding: [camera.mac])

        func usable(_ value: UInt32) -> Bool {
            value > network && value < broadcast && !used.contains(IPv4(value))
        }
        let kept = network | (camera.ipv4.value & ~mask)
        if usable(kept) { return IPv4(kept) }
        let start = min(network + 10, broadcast - 1)
        let candidate = (start..<broadcast).first(where: usable) ?? (network + 1..<broadcast).first(where: usable)
        return IPv4(candidate ?? kept)
    }

    func webURL(for camera: Camera) -> URL? {
        URL(string: camera.httpPort == 80 ? "http://\(camera.ipv4)/" : "http://\(camera.ipv4):\(camera.httpPort)/")
    }
}
