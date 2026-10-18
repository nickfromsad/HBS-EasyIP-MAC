import EasyIPKit
import SwiftUI

/// Gives the Mac an extra IP address in a camera's subnet, so the camera's web interface (and
/// everything else on that subnet) can be reached without touching the camera's settings.
struct JoinSubnetSheet: View {
    let camera: Camera
    @Environment(ScannerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var netmask: String
    @State private var interfaceID: String
    @State private var failure: String?
    @State private var isWorking = false

    init(camera: Camera, suggestion: IPv4, interface: NetworkInterface?) {
        self.camera = camera
        _address = State(initialValue: suggestion.description)
        _netmask = State(initialValue: (camera.netmask.prefixLength > 0 ? camera.netmask : IPv4("255.255.255.0")!).description)
        _interfaceID = State(initialValue: interface?.id ?? "")
    }

    private var ports: [NetworkInterface] {
        var seen = Set<String>()
        return model.interfaces.filter { seen.insert($0.bsdName).inserted }
    }
    private var port: NetworkInterface? { ports.first { $0.id == interfaceID } ?? ports.first }
    private var subnet: String {
        guard let mask = IPv4(netmask) else { return "?" }
        return "\(IPv4(camera.ipv4.value & mask.value))/\(mask.prefixLength)"
    }
    private var problem: String? {
        guard let ip = IPv4(address), let mask = IPv4(netmask) else { return "Enter a valid IP address and subnet mask." }
        if !ip.sameSubnet(as: camera.ipv4, mask: mask) { return "\(ip) is not in the camera's subnet \(subnet)." }
        return model.aliasProblem(address: ip, netmask: mask, on: port)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HBSSheetHeader(
                title: "Join Camera Subnet",
                subtitle: "\(model.name(of: camera))  ·  \(camera.model)  ·  \(camera.ipv4.description)  ·  subnet \(subnet)"
            )

            VStack(alignment: .leading, spacing: 10) {
                HBSGroup(title: "What happens") {
                    explanation
                }

                HBSGroup(title: "Extra IP address for this Mac") {
                    HBSSettingRow(label: "Network port:", description: "The port the camera answered on is selected.") {
                        Picker("", selection: $interfaceID) {
                            ForEach(ports) { port in
                                Text("\(port.displayName)  (\(port.bsdName))").tag(port.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 260)
                    }
                    HBSSettingRow(label: "IP address:", description: "A free address in the camera's subnet. Change it if other equipment (switcher, router, intercom) might use this one.") {
                        AddressField(text: $address)
                    }
                    HBSSettingRow(label: "Subnet mask:") { AddressField(text: $netmask) }
                }

                if let problem {
                    StatusDot(text: problem, color: HBS.orange)
                } else if let failure {
                    Text("● " + failure)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HBS.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Text("macOS asks for your administrator password.")
                        .font(.system(size: 11))
                        .foregroundStyle(HBS.label)
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(HBSButtonStyle())
                    Button("Add IP Address") { add() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(HBSButtonStyle(prominent: true))
                        .disabled(problem != nil || isWorking)
                }
                .padding(.top, 4)
            }
            .padding(14)
        }
        .frame(width: 600)
        .background(HBS.background)
        .preferredColorScheme(.dark)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            bullet("This Mac gets **an extra IP address, \(address)**, in the camera's subnet **\(subnet)**, on \(port?.displayName ?? "the selected port").")
            bullet("Your current address **\(port?.ipv4.description ?? "")** stays as it is, so the network you are on keeps working.")
            bullet("**Nothing changes on the camera** or on the rig. You can then open the camera's web interface and reach everything else in \(subnet).")
            bullet("The extra address is removed when you click **Remove** in the Network section or quit EasyIP MAC, and also when the cable is unplugged or the Mac restarts.")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(HBS.green)
            Text(.init(text))
                .font(.system(size: 12))
                .foregroundStyle(HBS.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func add() {
        guard let ip = IPv4(address), let mask = IPv4(netmask), let port else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        do {
            try model.addAlias(address: ip, netmask: mask, on: port)
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
