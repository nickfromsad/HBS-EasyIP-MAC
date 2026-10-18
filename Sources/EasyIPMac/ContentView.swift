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
    @AppStorage("logOpen") private var logOpen = true

    private var rows: [Camera] { model.cameras.sorted(using: sortOrder) }
    private var selectedCameras: [Camera] { rows.filter { selection.contains($0.mac) } }

    var body: some View {
        VStack(spacing: 0) {
            HBSHeader()
            VStack(spacing: 10) {
                networkGroup
                camerasGroup
                logGroup
                searchButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(HBS.background)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .tint(HBS.lightGrey)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case let .settings(camera): CameraSettingsSheet(camera: camera)
            case let .autoIP(cameras): AutoIPSheet(cameras: cameras)
            }
        }
        #if DEBUG
        // Development aid for screenshots: EASYIP_DEBUG_SHEET=settings|autoip opens a sheet after the first search.
        .task {
            guard let which = ProcessInfo.processInfo.environment["EASYIP_DEBUG_SHEET"] else { return }
            try? await Task.sleep(for: .seconds(4))
            let fakes = rows.filter { $0.mac.bytes.first == 0x02 }
            guard let first = fakes.first else { return }
            sheet = which == "autoip" ? .autoIP(fakes) : .settings(first)
        }
        #endif
        .alert("HBS // EasyIP MAC", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: Network

    private var networkGroup: some View {
        HBSGroup(title: "Network") {
            HStack(spacing: 14) {
                if model.interfaces.isEmpty {
                    Text("No network connection").font(.system(size: 12)).foregroundStyle(HBS.label)
                }
                ForEach(model.interfaces) { interface in
                    HStack(spacing: 6) {
                        Text(interface.displayName).foregroundStyle(HBS.text)
                        Text("\(interface.ipv4.description)/\(interface.netmask.prefixLength)")
                            .monospacedDigit()
                            .foregroundStyle(HBS.label)
                    }
                    .font(.system(size: 12))
                }
                Spacer()
                searchStatus
            }
        }
    }

    @ViewBuilder private var searchStatus: some View {
        if model.isSearching {
            StatusDot(text: "Searching…", color: HBS.orange)
        } else if model.cameras.isEmpty {
            StatusDot(text: "No cameras", color: HBS.red)
        } else {
            StatusDot(text: model.cameras.count == 1 ? "1 device" : "\(model.cameras.count) devices", color: HBS.green)
        }
    }

    // MARK: Cameras

    private var camerasGroup: some View {
        HBSGroup(title: "Cameras") {
            table
                .overlay { emptyState }
                .frame(minHeight: 180)
            HStack(spacing: 6) {
                Button("Web Interface") { selectedCameras.first.map(openWeb) }
                    .disabled(selectedCameras.count != 1)
                    .help("Open the camera's web interface (double-click a row)")
                Button("Network Settings…") { selectedCameras.first.map { sheet = .settings($0) } }
                    .disabled(selectedCameras.count != 1)
                    .help("Change IP address, subnet mask, gateway and port")
                Button("Auto IP…") { sheet = .autoIP(selectedCameras) }
                    .disabled(selectedCameras.isEmpty)
                    .help("Give the selected cameras consecutive IP addresses")
                Button("Copy IP") { selectedCameras.first.map { copy($0.ipv4.description) } }
                    .disabled(selectedCameras.count != 1)
                Spacer()
                HBSTag(text: "OK", color: HBS.green)
                Text("reachable").legendStyle()
                HBSTag(text: "SUBNET", color: HBS.orange).padding(.leading, 6)
                Text("other subnet").legendStyle()
                HBSTag(text: "DUP IP", color: HBS.red).padding(.leading, 6)
                Text("duplicate").legendStyle()
            }
            .buttonStyle(HBSButtonStyle())
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("State") { camera in
                StatusTag(status: model.status(of: camera))
            }
            .width(min: 50, ideal: 56)
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
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .background(HBS.field)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: 0x3A3A3A)))
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
        if model.cameras.isEmpty && !model.isSearching {
            VStack(spacing: 6) {
                Text("No cameras found")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HBS.text)
                Text("Check the network cable, and that EasyIP MAC is allowed under\nSystem Settings → Privacy & Security → Local Network.\nCameras in any subnet are found, as long as they share the cable/switch/VLAN.")
                    .font(.system(size: 11))
                    .foregroundStyle(HBS.label)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
        }
    }

    // MARK: Log

    private var logGroup: some View {
        HBSGroup(title: "Log") {
            if logOpen {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(model.log) { line in
                                Text("\(line.time.formatted(date: .omitted, time: .standard))  \(line.text)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color(hex: 0xB0B0B0))
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                    }
                    .frame(height: 84)
                    .background(HBS.log)
                    .onChange(of: model.log.last?.id) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(logOpen ? "hide" : "show") { logOpen.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(HBS.groupTitle)
                .padding(.top, 9)
                .padding(.trailing, 10)
        }
    }

    // MARK: Search

    private var searchButton: some View {
        Button(model.isSearching ? "SEARCHING…" : "SEARCH CAMERAS") {
            Task { await model.search() }
        }
        .buttonStyle(HBSBigButtonStyle(active: model.isSearching))
        .disabled(model.isSearching)
        .keyboardShortcut("r")
        .help("Search all networks for Panasonic cameras (⌘R)")
    }

    // MARK: Actions

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
        model.addLog("Copied \(string)")
    }
}

struct StatusTag: View {
    let status: ReachStatus

    var body: some View {
        Group {
            switch status {
            case .reachable: HBSTag(text: "OK", color: HBS.green)
            case .otherSubnet: HBSTag(text: "SUBNET", color: HBS.orange)
            case .duplicateIP: HBSTag(text: "DUP IP", color: HBS.red)
            }
        }
        .help(status.label)
        .accessibilityLabel(status.label)
    }
}

private extension Text {
    func legendStyle() -> some View {
        font(.system(size: 11)).foregroundStyle(HBS.label)
    }
}
