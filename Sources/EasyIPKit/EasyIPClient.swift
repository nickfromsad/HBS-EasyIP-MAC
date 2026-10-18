import Foundation

public enum ReconfigureError: LocalizedError {
    case noInterfaces
    case noResponse

    public var errorDescription: String? {
        switch self {
        case .noInterfaces: "No active network connection with an IPv4 address."
        case .noResponse:
            """
            The camera did not respond. Easy IP changes are only accepted during the first 20 minutes \
            after the camera is powered on, unless “Easy IP Setup accommodate period” is set to \
            “Unlimited” in the camera's network settings. Power-cycle the camera and try again.
            """
        }
    }
}

/// Searches for cameras and changes their network settings. Shared by the app and `domescan`.
@MainActor
public final class EasyIPClient {
    /// Called for every camera announcement (also repeats for cameras already seen).
    public var onCamera: ((Camera) -> Void)?
    public private(set) var interfaces: [NetworkInterface] = []

    private var socket: EasyIPSocket!
    private var acks: [MACAddress: EasyIP.Host] = [:]

    public init() throws {
        socket = try EasyIPSocket { [weak self] message in
            Task { @MainActor in self?.handle(message) }
        }
    }

    public func stop() { socket.stop() }

    /// Re-reads the Mac's network interfaces. Called automatically by search and reconfigure.
    @discardableResult
    public func refreshInterfaces() -> [NetworkInterface] {
        interfaces = NetworkInterface.all()
        return interfaces
    }

    /// Broadcasts a search on every interface, three times because UDP may drop a packet.
    /// Replies arrive through `onCamera` while this runs and shortly after.
    public func search(duration: Duration = .seconds(3)) async throws {
        guard !refreshInterfaces().isEmpty else { throw ReconfigureError.noInterfaces }
        let clock = ContinuousClock()
        let end = clock.now + duration
        for _ in 0..<3 {
            try broadcast { EasyIP.searchRequest(from: $0.host) }
            try? await Task.sleep(for: .milliseconds(500))
        }
        try? await Task.sleep(until: end, clock: clock)
    }

    /// Request → camera ack → commit, the same three-step handshake as Panasonic's tool.
    /// `camera` must come from an announcement: some of its fields are echoed back.
    public func reconfigure(_ camera: Camera, to settings: NetworkSettings) async throws {
        guard !refreshInterfaces().isEmpty else { throw ReconfigureError.noInterfaces }
        acks[camera.mac] = nil

        for _ in 0..<3 {
            try broadcast { EasyIP.reconfigureRequest(for: camera, settings: settings, from: $0.host) }
            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(100))
                guard let host = acks.removeValue(forKey: camera.mac) else { continue }
                let via = interfaces.filter { $0.ipv4 == host.ipv4 }
                try broadcast(via: via.isEmpty ? interfaces : via) { _ in
                    EasyIP.reconfigureCommit(for: camera.mac, from: host)
                }
                return
            }
        }
        throw ReconfigureError.noResponse
    }

    private func handle(_ message: EasyIP.Message) {
        switch message {
        case let .announcement(camera):
            onCamera?(camera)
        case let .reconfigureAck(camera, host):
            acks[camera] = host
        }
    }

    /// Sends one packet per interface. Fails only if no interface could send at all.
    private func broadcast(via subset: [NetworkInterface]? = nil, packet: (NetworkInterface) -> [UInt8]) throws {
        var lastError: Error?
        var sent = 0
        for interface in subset ?? interfaces {
            do {
                try socket.broadcast(packet(interface), via: interface)
                sent += 1
            } catch {
                lastError = error
            }
        }
        if sent == 0, let lastError { throw lastError }
    }
}
