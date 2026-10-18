import EasyIPKit
import SwiftUI

enum ActiveSheet: Identifiable {
    case settings(Camera)
    case autoIP([Camera])

    var id: String {
        switch self {
        case let .settings(camera): "settings-\(camera.mac)"
        case let .autoIP(cameras): "auto-" + cameras.map(\.mac.description).joined()
        }
    }
}

struct ContentView: View {
    @Environment(ScannerModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var selection = Set<MACAddress>()
    @State private var sortOrder = [KeyPathComparator(\Camera.ipv4)]
    @State private var sheet: ActiveSheet?

    private var rows: [Camera] { model.cameras.sorted(using: sortOrder) }
    private var selectedCameras: [Camera] { rows.filter { selection.contains($0.mac) } }

    var body: some View {
        table
            .overlay { emptyState }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case let .settings(camera): CameraSettingsSheet(camera: camera)
                case let .autoIP(cameras): AutoIPSheet(cameras: cameras)
                }
            }
            .alert("Dome Scanner", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { camera in
                StatusIcon(status: model.status(of: camera))
            }
            .width(22)
            TableColumn("IP Address", value: \.ipv4) { Text($0.ipv4.description).monospacedDigit() }
                .width(min: 110, ideal: 120)
            TableColumn("Title", value: \.title)
                .width(min: 80, ideal: 120)
            TableColumn("Model", value: \.model)
                .width(min: 60, ideal: 80)
            TableColumn("Type", value: \.category)
                .width(min: 36, ideal: 44)
            TableColumn("MAC Address", value: \.mac) { Text($0.mac.description).monospaced() }
                .width(min: 130, ideal: 140)
            TableColumn("Subnet Mask", value: \.netmask) { Text($0.netmask.description).monospacedDigit() }
                .width(min: 100, ideal: 110)
            TableColumn("Gateway", value: \.gateway) { Text($0.gateway.description).monospacedDigit() }
                .width(min: 100, ideal: 110)
            TableColumn("Port", value: \.httpPort) { Text($0.httpPort == 0 ? "–" : String($0.httpPort)).monospacedDigit() }
                .width(min: 40, ideal: 50)
        }
        .contextMenu(forSelectionType: MACAddress.self) { macs in
            let cameras = rows.filter { macs.contains($0.mac) }
            if cameras.count == 1, let camera = cameras.first {
                Button("Open Web Interface") { openWeb(camera) }
                Button("Network Settings…") { sheet = .settings(camera) }
                Divider()
                Button("Copy IP Address") { copy(camera.ipv4.description) }
                Button("Copy MAC Address") { copy(camera.mac.description) }
            }
            if !cameras.isEmpty {
                Button("Auto IP…") { sheet = .autoIP(cameras) }
            }
        } primaryAction: { macs in
            if macs.count == 1, let camera = rows.first(where: { macs.contains($0.mac) }) {
                openWeb(camera)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.cameras.isEmpty {
            if model.isSearching {
                ProgressView("Searching…")
            } else {
                ContentUnavailableView {
                    Label("No Cameras Found", systemImage: "video.slash")
                } description: {
                    Text("Check the network cable and that Dome Scanner is allowed under System Settings → Privacy & Security → Local Network. Cameras in any subnet are found, as long as they are on the same physical network.")
                } actions: {
                    Button("Search Again") { Task { await model.search() } }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Text(model.cameras.count == 1 ? "1 camera" : "\(model.cameras.count) cameras")
            Text("·").foregroundStyle(.tertiary)
            Text(interfaceSummary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var interfaceSummary: String {
        if model.interfaces.isEmpty { return "No network" }
        return "Searching on " + model.interfaces
            .map { "\($0.displayName) \($0.ipv4)/\($0.netmask.prefixLength)" }
            .joined(separator: ", ")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                if let camera = selectedCameras.first { openWeb(camera) }
            } label: {
                Label("Web Interface", systemImage: "safari")
            }
            .disabled(selectedCameras.count != 1)
            .help("Open the camera's web interface")

            Button {
                if let camera = selectedCameras.first { sheet = .settings(camera) }
            } label: {
                Label("Network Settings", systemImage: "network")
            }
            .disabled(selectedCameras.count != 1)
            .help("Change IP address, subnet mask, gateway and port")

            Button {
                sheet = .autoIP(selectedCameras)
            } label: {
                Label("Auto IP", systemImage: "list.number")
            }
            .disabled(selectedCameras.isEmpty)
            .help("Give the selected cameras consecutive IP addresses")

            Button {
                Task { await model.search() }
            } label: {
                if model.isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Search", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isSearching)
            .help("Search for cameras (⌘R)")
        }
    }

    private func openWeb(_ camera: Camera) {
        if case .otherSubnet = model.status(of: camera) {
            model.errorMessage = "\(camera.ipv4) is in a different subnet than this Mac, so its web interface cannot be opened. Use Network Settings to move it into your subnet first."
            return
        }
        if let url = model.webURL(for: camera) { openURL(url) }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

struct StatusIcon: View {
    let status: ReachStatus

    var body: some View {
        Group {
            switch status {
            case .reachable: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .otherSubnet: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .duplicateIP: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
        .help(status.label)
        .accessibilityLabel(status.label)
    }
}
