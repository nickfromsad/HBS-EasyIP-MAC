import EasyIPKit
import SwiftUI

/// Gives several cameras consecutive addresses, e.g. a batch of new cameras that all
/// arrive with the factory default 192.168.0.10.
struct AutoIPSheet: View {
    let cameras: [Camera]
    @Environment(ScannerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var startAddress: String
    @State private var netmask: String
    @State private var gateway: String
    @State private var results: [MACAddress: Result] = [:]
    @State private var isApplying = false

    enum Result {
        case working, done, failed(String)
    }

    init(cameras: [Camera]) {
        self.cameras = cameras
        let first = cameras.first?.settings
        _startAddress = State(initialValue: first?.ipv4.description ?? "")
        _netmask = State(initialValue: first?.netmask.description ?? "255.255.255.0")
        _gateway = State(initialValue: first?.gateway.description ?? "0.0.0.0")
    }

    /// New address per camera, skipping addresses used by this Mac or by cameras not in the batch.
    private var plan: [(camera: Camera, address: IPv4)]? {
        guard let start = IPv4(startAddress), let mask = IPv4(netmask), mask.prefixLength > 0 else { return nil }
        let used = model.addressesInUse(excluding: Set(cameras.map(\.mac)))
        let broadcast = start.value | ~mask.value
        var next = start.value
        var plan: [(Camera, IPv4)] = []
        for camera in cameras {
            while used.contains(IPv4(next)) && next < broadcast { next += 1 }
            guard next < broadcast, IPv4(next).sameSubnet(as: start, mask: mask) else { return nil }
            plan.append((camera, IPv4(next)))
            next += 1
        }
        return plan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto IP").font(.headline)
                Text("Assign consecutive addresses to \(cameras.count) camera\(cameras.count == 1 ? "" : "s"), in table order.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 20)

            Form {
                Section {
                    AddressField(title: "Start Address", text: $startAddress)
                    AddressField(title: "Subnet Mask", text: $netmask)
                    AddressField(title: "Default Gateway", text: $gateway)
                    if !model.interfaces.isEmpty {
                        Menu("Use Subnet of This Mac") {
                            ForEach(model.interfaces) { interface in
                                Button("\(interface.displayName)  \(interface.ipv4.description)/\(interface.netmask.prefixLength)") {
                                    useSubnet(of: interface)
                                }
                            }
                        }
                    }
                }
                Section("Preview") {
                    if let plan {
                        ForEach(plan, id: \.camera.mac) { item in
                            HStack {
                                Text(item.camera.title).frame(width: 110, alignment: .leading).lineLimit(1)
                                Text(item.camera.mac.description).monospaced().foregroundStyle(.secondary)
                                Spacer()
                                Text("\(item.camera.ipv4.description)  →  \(item.address.description)").monospacedDigit()
                                resultIcon(for: item.camera.mac).frame(width: 18)
                            }
                        }
                    } else {
                        Text("The start address and subnet mask must leave room for every camera.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isApplying)

            HStack {
                if isApplying { ProgressView().controlSize(.small) }
                Spacer()
                Button(results.isEmpty ? "Cancel" : "Close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Assign") { Task { await apply() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan == nil || IPv4(gateway) == nil || isApplying)
            }
            .padding(20)
        }
        .frame(width: 520, height: 520)
    }

    @ViewBuilder private func resultIcon(for mac: MACAddress) -> some View {
        switch results[mac] {
        case .working: ProgressView().controlSize(.mini)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case let .failed(message): Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help(message)
        case nil: EmptyView()
        }
    }

    private func useSubnet(of interface: NetworkInterface) {
        let network = interface.ipv4.value & interface.netmask.value
        startAddress = IPv4(network + 10).description
        netmask = interface.netmask.description
        if let gw = IPv4(gateway), !interface.contains(gw) { gateway = "0.0.0.0" }
    }

    private func apply() async {
        guard let plan, let mask = IPv4(netmask), let gw = IPv4(gateway) else { return }
        isApplying = true
        results = [:]
        defer { isApplying = false }

        for (camera, address) in plan {
            results[camera.mac] = .working
            var settings = camera.settings
            settings.ipv4 = address
            settings.netmask = mask
            settings.gateway = gw
            do {
                try await model.apply(settings, to: camera)
                results[camera.mac] = .done
            } catch {
                results[camera.mac] = .failed(error.localizedDescription)
            }
        }
        model.searchAgain()
        let failures = results.values.filter { if case .failed = $0 { true } else { false } }
        if failures.isEmpty { dismiss() }
    }
}
