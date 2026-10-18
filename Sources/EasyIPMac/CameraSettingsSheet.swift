import EasyIPKit
import SwiftUI

/// Text-field state for the settings Easy IP can change, with validation.
struct SettingsForm {
    var ipv4: String
    var netmask: String
    var gateway: String
    var primaryDNS: String
    var secondaryDNS: String
    var httpPort: String

    init(_ settings: NetworkSettings) {
        ipv4 = settings.ipv4.description
        netmask = settings.netmask.description
        gateway = settings.gateway.description
        primaryDNS = settings.primaryDNS.description
        secondaryDNS = settings.secondaryDNS.description
        httpPort = String(settings.httpPort)
    }

    var settings: NetworkSettings? {
        guard let ip = IPv4(ipv4), ip != .zero,
              let mask = IPv4(netmask), mask.prefixLength > 0,
              let gw = IPv4(gateway),
              let dns1 = IPv4(primaryDNS), let dns2 = IPv4(secondaryDNS),
              let port = UInt16(httpPort), port > 0 else { return nil }
        return NetworkSettings(ipv4: ip, netmask: mask, gateway: gw, primaryDNS: dns1, secondaryDNS: dns2, httpPort: port)
    }
}

/// HBS-styled text field that turns red while the input is invalid.
struct AddressField: View {
    @Binding var text: String
    var width: CGFloat = 140
    var validate: (String) -> Bool = { IPv4($0) != nil }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(HBSFieldStyle(valid: validate(text)))
            .frame(width: width)
    }
}

struct CameraSettingsSheet: View {
    let camera: Camera
    @Environment(ScannerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var form: SettingsForm
    @State private var isApplying = false
    @State private var failure: String?

    init(camera: Camera) {
        self.camera = camera
        _form = State(initialValue: SettingsForm(camera.settings))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HBSSheetHeader(
                title: "Network Settings",
                subtitle: "\(camera.title)  ·  \(camera.model)  ·  \(camera.mac.description)  ·  now \(camera.ipv4.description)"
            )

            VStack(alignment: .leading, spacing: 10) {
                HBSGroup(title: "Camera") {
                    HBSSettingRow(label: "IP address:") { AddressField(text: $form.ipv4) }
                    HBSSettingRow(label: "Subnet mask:") { AddressField(text: $form.netmask) }
                    HBSSettingRow(label: "Default gateway:", description: "Use 0.0.0.0 when the network has no router.") {
                        AddressField(text: $form.gateway)
                    }
                    HBSSettingRow(label: "HTTP port:") {
                        AddressField(text: $form.httpPort, width: 60) { UInt16($0).map { $0 > 0 } ?? false }
                    }
                    HBSSettingRow(label: "DNS:") {
                        AddressField(text: $form.primaryDNS, width: 120)
                        AddressField(text: $form.secondaryDNS, width: 120)
                    }
                }

                if !model.interfaces.isEmpty {
                    HBSGroup(title: "Move into the subnet of this Mac") {
                        HStack(spacing: 6) {
                            ForEach(model.interfaces) { interface in
                                Button("\(interface.displayName)  \(interface.ipv4.description)/\(interface.netmask.prefixLength)") {
                                    moveInto(interface)
                                }
                            }
                        }
                        .buttonStyle(HBSButtonStyle())
                        Text("Fills in a free address in that subnet, so you can reach the camera's web interface.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0x777777))
                    }
                }

                if camera.easyIPLocked {
                    Text("● This camera reports that Easy IP changes are locked (experimental). It was probably powered on more than 20 minutes ago: power-cycle it, or set “Easy IP Setup accommodate period” to Unlimited in its web interface.")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HBS.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let warning = collisionWarning {
                    StatusDot(text: warning, color: HBS.orange)
                }
                if let failure {
                    Text("● " + failure)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(HBS.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if isApplying {
                        StatusDot(text: "Sending…", color: HBS.orange)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(HBSButtonStyle())
                    Button("Apply") { Task { await apply() } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(HBSButtonStyle(prominent: true))
                        .disabled(form.settings == nil || form.settings == camera.settings || isApplying)
                }
                .padding(.top, 4)
            }
            .padding(14)
            .disabled(isApplying)
        }
        .frame(width: 520)
        .background(HBS.background)
        .preferredColorScheme(.dark)
    }

    private var collisionWarning: String? {
        guard let ip = IPv4(form.ipv4), ip != camera.ipv4,
              model.addressesInUse(excluding: [camera.mac]).contains(ip) else { return nil }
        return "\(ip) is already used by this Mac or another camera"
    }

    private func moveInto(_ interface: NetworkInterface) {
        form.ipv4 = model.suggestedAddress(for: camera, in: interface).description
        form.netmask = interface.netmask.description
        if let gateway = IPv4(form.gateway), gateway != .zero, !interface.contains(gateway) {
            form.gateway = "0.0.0.0"
        }
    }

    private func apply() async {
        guard let settings = form.settings else { return }
        isApplying = true
        failure = nil
        defer { isApplying = false }
        do {
            try await model.apply(settings, to: camera)
            model.searchAgain()
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}
