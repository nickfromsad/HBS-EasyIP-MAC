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

struct AddressField: View {
    let title: String
    @Binding var text: String
    var validate: (String) -> Bool = { IPv4($0) != nil }

    var body: some View {
        TextField(title, text: $text)
            .monospacedDigit()
            .foregroundStyle(validate(text) ? Color.primary : Color.red)
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Network Settings").font(.headline)
                Text("\(camera.title)  ·  \(camera.model)  ·  \(camera.mac.description)  ·  currently \(camera.ipv4.description)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 20)

            Form {
                Section {
                    AddressField(title: "IP Address", text: $form.ipv4)
                    AddressField(title: "Subnet Mask", text: $form.netmask)
                    AddressField(title: "Default Gateway", text: $form.gateway)
                    AddressField(title: "HTTP Port", text: $form.httpPort) { UInt16($0).map { $0 > 0 } ?? false }
                }
                Section {
                    AddressField(title: "Primary DNS", text: $form.primaryDNS)
                    AddressField(title: "Secondary DNS", text: $form.secondaryDNS)
                }
                if !model.interfaces.isEmpty {
                    Section("Move into a subnet of this Mac") {
                        ForEach(model.interfaces) { interface in
                            Button("\(interface.displayName)  \(interface.ipv4.description)/\(interface.netmask.prefixLength)") {
                                moveInto(interface)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                if let warning = collisionWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let failure {
                    Label(failure, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .disabled(isApplying)

            HStack {
                if isApplying { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") { Task { await apply() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(form.settings == nil || form.settings == camera.settings || isApplying)
            }
            .padding(20)
        }
        .frame(width: 440)
    }

    private var collisionWarning: String? {
        guard let ip = IPv4(form.ipv4), ip != camera.ipv4,
              model.addressesInUse(excluding: [camera.mac]).contains(ip) else { return nil }
        return "\(ip) is already used by this Mac or another camera."
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
