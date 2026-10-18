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
        case .otherSubnet: "Other subnet: not reachable from this Mac. Use “Join Subnet” or change the camera's IP"
        case .duplicateIP: "Duplicate IP: another camera uses the same address"
        }
    }
}

@MainActor @Observable
final class ScannerModel {
    private(set) var cameras: [Camera] = []
    private(set) var interfaces: [NetworkInterface] = []
    /// True while a search started by the user runs (drives the big button); auto rounds stay quiet.
    private(set) var isSearching = false
    private(set) var log: [LogLine] = []
    /// Short-lived "+ HOF-121 appeared" notice next to the status in the Network group.
    private(set) var lastEvent: String?
    private(set) var availableUpdate: UpdateCheck.Release?
    /// Extra IP addresses this app added to the Mac (see SubnetAlias); remembered across launches.
    private(set) var aliases: [SubnetAlias] = []
    var errorMessage: String? {
        didSet { if let errorMessage { addLog("✗ " + errorMessage) } }
    }

    var autoSearch = UserDefaults.standard.bool(forKey: "autoSearch") {
        didSet {
            UserDefaults.standard.set(autoSearch, forKey: "autoSearch")
            addLog(autoSearch ? "Auto search on, every \(autoInterval) s" : "Auto search off")
            restartAutoSearch()
        }
    }
    var autoInterval = UserDefaults.standard.object(forKey: "autoInterval") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(autoInterval, forKey: "autoInterval") }
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
    }

    private var client: EasyIPClient?
    private var autoTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var roundRunning = false
    private var completedRounds = 0
    private var seenThisRound = Set<MACAddress>()
    private var missedRounds: [MACAddress: Int] = [:]
    private var seenVia: [MACAddress: NetworkInterface] = [:]

    func start() {
        guard client == nil else { return }
        do {
            let client = try EasyIPClient()
            client.onCamera = { [weak self] camera, interface in self?.add(camera, via: interface) }
            self.client = client
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        interfaces = NetworkInterface.all()
        restoreAliases()
        Task { await search() }
        restartAutoSearch()
        Task { availableUpdate = await UpdateCheck.newerRelease(than: HBS.version) }
    }

    // MARK: Search

    /// Searches on every interface. The list is updated in place: cameras that stop answering are
    /// removed after one silent round (two in auto mode, where UDP loss would otherwise flicker).
    func search() async {
        guard client != nil else { return start() }
        isSearching = true
        await runRound(manual: true)
        isSearching = false
    }

    private func runRound(manual: Bool) async {
        guard let client, !roundRunning else { return }
        roundRunning = true
        defer { roundRunning = false }

        interfaces = client.refreshInterfaces()
        seenThisRound.removeAll()
        if manual {
            addLog("▶ Search on " + interfaces.map { "\($0.bsdName) \($0.ipv4)/\($0.netmask.prefixLength)" }.joined(separator: ", "))
        }
        do {
            try await client.search(duration: manual ? .seconds(3) : .seconds(2))
        } catch {
            if manual || completedRounds == 0 { errorMessage = error.localizedDescription }
            return
        }

        for camera in cameras where !seenThisRound.contains(camera.mac) {
            missedRounds[camera.mac, default: 0] += 1
        }
        let gone = cameras.filter { (missedRounds[$0.mac] ?? 0) >= (manual ? 1 : 2) }
        for camera in gone {
            cameras.removeAll { $0.mac == camera.mac }
            missedRounds[camera.mac] = nil
            seenVia[camera.mac] = nil
            announce("− \(name(of: camera)) \(camera.ipv4) disappeared")
        }
        completedRounds += 1

        if manual {
            let otherSubnet = cameras.filter { status(of: $0) == .otherSubnet }.count
            let duplicates = cameras.filter { status(of: $0) == .duplicateIP }.count
            addLog("✓ Found \(cameras.count) device(s)"
                + (otherSubnet > 0 ? ", \(otherSubnet) in another subnet" : "")
                + (duplicates > 0 ? ", \(duplicates) with a duplicate IP" : ""))
        }
    }

    private func restartAutoSearch() {
        autoTask?.cancel()
        guard autoSearch else { return }
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(autoInterval))
                guard !Task.isCancelled, autoSearch else { return }
                await runRound(manual: false)
            }
        }
    }

    /// Cameras restart their network stack after a change; search again once they are back.
    func searchAgain(after delay: Duration = .seconds(3)) {
        Task {
            try? await Task.sleep(for: delay)
            await search()
        }
    }

    private func add(_ camera: Camera, via interface: NetworkInterface?) {
        seenThisRound.insert(camera.mac)
        missedRounds[camera.mac] = 0
        if let interface { seenVia[camera.mac] = interface }
        if let index = cameras.firstIndex(where: { $0.mac == camera.mac }) {
            let old = cameras[index]
            cameras[index] = camera
            if old.ipv4 != camera.ipv4 {
                announce("~ \(name(of: camera)) is now \(camera.ipv4) (was \(old.ipv4))")
            }
        } else {
            cameras.append(camera)
            if completedRounds > 0 {
                announce("+ \(name(of: camera)) \(camera.ipv4) appeared" + (interface.map { " on \($0.bsdName)" } ?? ""))
            }
        }
    }

    func addLog(_ text: String) {
        log.append(LogLine(text: text))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    /// Logs a camera coming or going and shows it briefly next to the status.
    private func announce(_ text: String) {
        addLog(text)
        lastEvent = text
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { self?.lastEvent = nil }
        }
    }

    func name(of camera: Camera) -> String {
        camera.title.isEmpty ? camera.model : camera.title
    }

    // MARK: Reconfigure

    func apply(_ settings: NetworkSettings, to camera: Camera) async throws {
        guard let client else { throw ReconfigureError.noInterfaces }
        let name = name(of: camera)
        addLog("▶ \(name) (\(camera.mac)): \(camera.ipv4) → \(settings.ipv4)/\(settings.netmask.prefixLength) gw \(settings.gateway)")
        do {
            try await client.reconfigure(camera, to: settings)
        } catch {
            addLog("✗ \(name): no response from camera (20-minute window?)")
            throw error
        }
        addLog("✓ \(name) accepted the new settings")
        interfaces = client.interfaces
    }

    // MARK: Join subnet (extra IP address on the Mac)

    /// The port a camera answered on, or the first port if unknown.
    func interface(for camera: Camera) -> NetworkInterface? {
        seenVia[camera.mac] ?? interfaces.first
    }

    /// A free address in the camera's subnet for the Mac, counting down from .250 and avoiding
    /// every camera, every camera's gateway, and the usual .1 / .254 router addresses.
    func suggestedAlias(for camera: Camera) -> IPv4 {
        let mask = camera.netmask.prefixLength > 0 ? camera.netmask.value : 0xFFFF_FF00
        let network = camera.ipv4.value & mask
        let broadcast = network | ~mask
        let taken = Set(cameras.map(\.ipv4.value) + cameras.map(\.gateway.value) + [network + 1, broadcast - 1])
        let start = min(network + 250, broadcast - 2)
        let candidate = stride(from: start, to: network, by: -1).first { !taken.contains($0) }
        return IPv4(candidate ?? network + 2)
    }

    /// Why `address`/`netmask` can't be used as an extra Mac address on `interface`, or nil if fine.
    func aliasProblem(address: IPv4, netmask: IPv4, on interface: NetworkInterface?) -> String? {
        guard interface != nil else { return "No network port selected." }
        guard netmask.prefixLength >= 8 else { return "Subnet mask is not valid." }
        let network = address.value & netmask.value
        if address.value == network || address.value == network | ~netmask.value {
            return "\(address) is the network or broadcast address of this subnet."
        }
        if let camera = cameras.first(where: { $0.ipv4 == address }) {
            return "\(address) is used by \(name(of: camera))."
        }
        if let existing = interfaces.first(where: { $0.contains(address) }) {
            return "This Mac is already in that subnet (\(existing.bsdName) \(existing.ipv4))."
        }
        return nil
    }

    func addAlias(address: IPv4, netmask: IPv4, on interface: NetworkInterface) throws {
        let alias = SubnetAlias(bsdName: interface.bsdName, address: address, netmask: netmask)
        addLog("▶ Adding \(address)/\(netmask.prefixLength) to \(interface.displayName) (\(interface.bsdName))")
        do {
            try SubnetAlias.add(alias)
        } catch {
            addLog("✗ " + error.localizedDescription)
            throw error
        }
        aliases.append(alias)
        saveAliases()
        interfaces = NetworkInterface.all()
        addLog("✓ This Mac is now also \(address) on \(interface.bsdName)")
        searchAgain(after: .seconds(1))
    }

    func removeAliases(_ list: [SubnetAlias]) throws {
        guard !list.isEmpty else { return }
        addLog("▶ Removing " + list.map { "\($0.address) from \($0.bsdName)" }.joined(separator: ", "))
        do {
            try SubnetAlias.remove(list)
        } catch {
            addLog("✗ " + error.localizedDescription)
            throw error
        }
        aliases.removeAll { list.contains($0) }
        saveAliases()
        interfaces = NetworkInterface.all()
        addLog("✓ Extra IP address removed")
    }

    func isAlias(_ interface: NetworkInterface) -> Bool {
        aliases.contains { $0.bsdName == interface.bsdName && $0.address == interface.ipv4 }
    }

    /// Keeps only aliases that still exist (unplugging a cable or a reboot removes them).
    private func restoreAliases() {
        guard let data = UserDefaults.standard.data(forKey: "aliases"),
              let saved = try? JSONDecoder().decode([SubnetAlias].self, from: data) else { return }
        aliases = saved.filter { alias in interfaces.contains { $0.bsdName == alias.bsdName && $0.ipv4 == alias.address } }
        saveAliases()
        if !aliases.isEmpty {
            addLog("Extra IP address still active from last time: " + aliases.map { "\($0.address) on \($0.bsdName)" }.joined(separator: ", "))
        }
    }

    private func saveAliases() {
        UserDefaults.standard.set(try? JSONEncoder().encode(aliases), forKey: "aliases")
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
