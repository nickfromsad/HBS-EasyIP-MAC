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
            HBSSheetHeader(
                title: "Auto IP",
                subtitle: "Consecutive addresses for \(cameras.count) camera\(cameras.count == 1 ? "" : "s"), in table order"
            )

            VStack(alignment: .leading, spacing: 10) {
                HBSGroup(title: "Addresses") {
                    HBSSettingRow(label: "Start address:", description: "Addresses already used by this Mac or other cameras are skipped.") {
                        AddressField(text: $startAddress)
                    }
                    HBSSettingRow(label: "Subnet mask:") { AddressField(text: $netmask) }
                    HBSSettingRow(label: "Default gateway:") { AddressField(text: $gateway) }
                    if !model.interfaces.isEmpty {
                        HBSSettingRow(label: "Use subnet of:") {
                            ForEach(model.interfaces) { interface in
                                Button("\(interface.displayName)  \(interface.ipv4.description)") {
                                    useSubnet(of: interface)
                                }
                                .buttonStyle(HBSButtonStyle())
                            }
                        }
                    }
                }

                HBSGroup(title: "Preview") {
                    if let plan {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(plan, id: \.camera.mac) { item in
                                    HStack(spacing: 10) {
                                        resultTag(for: item.camera.mac).frame(width: 46, alignment: .leading)
                                        Text(item.camera.title).foregroundStyle(HBS.text)
                                            .frame(width: 110, alignment: .leading).lineLimit(1)
                                        Text(item.camera.mac.description).monospaced().foregroundStyle(HBS.label)
                                            .lineLimit(1).fixedSize()
                                        Spacer()
                                        Text(item.camera.ipv4.description).foregroundStyle(HBS.label)
                                        Text("→").foregroundStyle(HBS.faint)
                                        Text(item.address.description).foregroundStyle(HBS.text)
                                            .frame(width: 110, alignment: .leading)
                                    }
                                    .font(.system(size: 12).monospacedDigit())
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    } else {
                        StatusDot(text: "The start address and subnet mask must leave room for every camera", color: HBS.red)
                    }
                }

                HStack(spacing: 8) {
                    if isApplying {
                        StatusDot(text: "Sending…", color: HBS.orange)
                    }
                    Spacer()
                    Button(results.isEmpty ? "Cancel" : "Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(HBSButtonStyle())
                    Button("Assign") { Task { await apply() } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(HBSButtonStyle(prominent: true))
                        .disabled(plan == nil || IPv4(gateway) == nil || isApplying)
                }
                .padding(.top, 4)
            }
            .padding(14)
            .disabled(isApplying)
        }
        .frame(width: 640)
        .background(HBS.background)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func resultTag(for mac: MACAddress) -> some View {
        switch results[mac] {
        case .working: HBSTag(text: "SEND", color: HBS.orange)
        case .done: HBSTag(text: "OK", color: HBS.green)
        case let .failed(message): HBSTag(text: "FAIL", color: HBS.red).help(message)
        case nil: HBSTag(text: "–", color: HBS.faint)
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
