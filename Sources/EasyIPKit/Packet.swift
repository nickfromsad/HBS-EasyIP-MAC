import Foundation

// Panasonic "Easy IP Setup" wire format, reconstructed from packet captures of the
// official Windows tool talking to an AW-HE130.
//
//   0  2  version        00 01
//   2  2  payload length (bytes between offset 48 and the FF FF trailer)
//   4  2  message type   (see MessageType)
//   6  6  camera MAC     (zero in a search request)
//  12  6  host MAC       (the PC/Mac running the tool)
//  18  4  host IPv4
//  22  2  handshake step
//  24 24  constant block (magic + mode)
//  48  n  payload
//  ..  2  FF FF
//  ..  2  checksum: sum of all preceding bytes + 1
//
// Everything is broadcast to 255.255.255.255: requests to UDP 10670, camera replies
// to UDP 10669. That is why it works across subnets: no routing, no ARP needed.

public enum EasyIP {
    public static let cameraPort: UInt16 = 10670
    public static let hostPort: UInt16 = 10669

    static let headerLength = 48
    static let trailerLength = 4
    static let magic: [UInt8] = [0x20, 0x11, 0x1E, 0x11, 0x23, 0x1F, 0x1E, 0x19, 0x13]
    static let searchMode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    static let configMode: [UInt8] = [0x00, 0x00, 0x02, 0x02]
    /// Payload preamble of a configuration announcement (camera -> host).
    static let announcePreamble: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x02, 0x00, 0x01, 0x00, 0x01, 0x00]
    /// Payload preamble of a reconfiguration request (host -> camera).
    static let reconfigurePreamble: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x03, 0x00, 0x01, 0x00, 0x01, 0x00]
    static let fieldsOffset = headerLength + 10

    public enum MessageType: UInt16, Sendable {
        case reconfigure = 0x02
        case reconfigureAck = 0x03
        case reconfigureCommit = 0x04
        case search = 0x0D
        case announcement = 0x0E
    }

    /// Type-length-value field identifiers seen in announcements and reconfigure requests.
    public enum Field: UInt16, CaseIterable, Sendable {
        case ipv4 = 0x20, netmask = 0x21, gateway = 0x22, dns = 0x23, httpPort = 0x25
        case ipv6LinkLocal = 0x40, ipv6Address = 0x41, ipv6Extra = 0x42, httpPortAlt = 0x44
        case ipv4Alt = 0xA0, netmaskAlt = 0xA1, gatewayAlt = 0xA2, dnsAlt = 0xA3
        case flags = 0xA6, title = 0xA7, categoryAndModel = 0xA8
    }

    /// Fields the official tool asks for in a search request.
    static let requestedFields: [UInt16] = [
        0x20, 0x21, 0x22, 0x23, 0x25, 0x28, 0x40, 0x41, 0x42, 0x44,
        0xA5, 0xA6, 0xA7, 0xA8, 0xAD, 0xB3, 0xB4, 0xB7, 0xB8,
    ]

    public struct Host: Hashable, Sendable {
        public var mac: MACAddress
        public var ipv4: IPv4
        public init(mac: MACAddress, ipv4: IPv4) {
            self.mac = mac
            self.ipv4 = ipv4
        }
    }

    // MARK: Building

    static func checksum(_ bytes: some Sequence<UInt8>) -> [UInt8] {
        let sum = bytes.reduce(UInt32(1)) { $0 &+ UInt32($1) }
        return be16(UInt16(truncatingIfNeeded: sum))
    }

    static func be16(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }

    static func frame(type: MessageType, camera: MACAddress?, host: Host, step: UInt16, mode: [UInt8], payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x00, 0x01]
        bytes += be16(UInt16(payload.count))
        bytes += be16(type.rawValue)
        bytes += camera?.bytes ?? [UInt8](repeating: 0, count: 6)
        bytes += host.mac.bytes
        bytes += host.ipv4.bytes
        bytes += be16(step)
        bytes += magic
        bytes += mode
        bytes += [UInt8](repeating: 0, count: headerLength - bytes.count)
        bytes += payload
        bytes += [0xFF, 0xFF]
        bytes += checksum(bytes)
        return bytes
    }

    public static func searchRequest(from host: Host) -> [UInt8] {
        var payload: [UInt8] = [0xFF, 0xF0] + be16(UInt16(requestedFields.count * 2))
        for field in requestedFields { payload += be16(field) }
        return frame(type: .search, camera: nil, host: host, step: 0, mode: searchMode, payload: payload)
    }

    /// Asks one camera (addressed by MAC) to adopt new network settings.
    /// The camera answers with `.reconfigureAck`, after which the host sends `reconfigureCommit`.
    public static func reconfigureRequest(for camera: Camera, settings: NetworkSettings, from host: Host) -> [UInt8] {
        func tlv(_ field: Field, _ value: [UInt8]) -> [UInt8] {
            be16(field.rawValue) + be16(UInt16(value.count)) + value
        }
        // IPv6 and flag fields are echoed back exactly as the camera announced them.
        func echo(_ field: Field) -> [UInt8] {
            camera.rawFields[field.rawValue].map { tlv(field, $0) } ?? []
        }
        let dns = settings.primaryDNS.bytes + settings.secondaryDNS.bytes
        let port = be16(settings.httpPort)

        var payload = reconfigurePreamble
        payload += tlv(.ipv4, settings.ipv4.bytes)
        payload += tlv(.netmask, settings.netmask.bytes)
        payload += tlv(.gateway, settings.gateway.bytes)
        payload += tlv(.dns, dns)
        payload += tlv(.httpPort, port)
        payload += echo(.ipv6LinkLocal)
        payload += echo(.ipv6Address)
        payload += echo(.ipv6Extra)
        payload += tlv(.httpPortAlt, port)
        payload += tlv(.ipv4Alt, settings.ipv4.bytes)
        payload += tlv(.netmaskAlt, settings.netmask.bytes)
        payload += tlv(.gatewayAlt, settings.gateway.bytes)
        payload += tlv(.dnsAlt, dns)
        payload += echo(.flags)
        return frame(type: .reconfigure, camera: camera.mac, host: host, step: 1, mode: configMode, payload: payload)
    }

    public static func reconfigureCommit(for camera: MACAddress, from host: Host) -> [UInt8] {
        frame(type: .reconfigureCommit, camera: camera, host: host, step: 2, mode: configMode, payload: [])
    }

    // MARK: Parsing

    public enum Message: Sendable, Equatable {
        case announcement(Camera)
        /// A camera accepted a reconfigure request sent by `host`.
        case reconfigureAck(camera: MACAddress, host: Host)
    }

    /// Validates framing and checksum, then decodes the messages a host cares about.
    public static func parse(_ bytes: [UInt8]) -> Message? {
        guard bytes.count >= headerLength + trailerLength,
              bytes[0] == 0x00, bytes[1] == 0x01,
              Array(bytes[24..<33]) == magic else { return nil }
        let payloadLength = Int(bytes[2]) << 8 | Int(bytes[3])
        guard bytes.count == headerLength + payloadLength + trailerLength,
              Array(bytes.suffix(2)) == checksum(bytes.dropLast(2)) else { return nil }

        let camera = MACAddress(bytes: bytes[6..<12])
        switch MessageType(rawValue: UInt16(bytes[4]) << 8 | UInt16(bytes[5])) {
        case .announcement:
            return Camera(mac: camera, fields: fields(in: bytes), statusFlags: bytes[fieldsOffset - 1])
                .map(Message.announcement)
        case .reconfigureAck:
            let host = Host(mac: MACAddress(bytes: bytes[12..<18]), ipv4: IPv4(bytes: bytes[18..<22]))
            return .reconfigureAck(camera: camera, host: host)
        default:
            return nil
        }
    }

    static func fields(in bytes: [UInt8]) -> [UInt16: [UInt8]] {
        var fields: [UInt16: [UInt8]] = [:]
        var cursor = fieldsOffset
        let end = bytes.count - trailerLength
        while cursor + 4 <= end {
            let id = UInt16(bytes[cursor]) << 8 | UInt16(bytes[cursor + 1])
            let length = Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3])
            guard cursor + 4 + length <= end else { break }
            fields[id] = Array(bytes[(cursor + 4)..<(cursor + 4 + length)])
            cursor += 4 + length
        }
        return fields
    }
}

/// The settings Easy IP can change on a camera.
public struct NetworkSettings: Hashable, Sendable {
    public var ipv4: IPv4
    public var netmask: IPv4
    public var gateway: IPv4
    public var primaryDNS: IPv4
    public var secondaryDNS: IPv4
    public var httpPort: UInt16

    public init(ipv4: IPv4, netmask: IPv4, gateway: IPv4, primaryDNS: IPv4 = .zero, secondaryDNS: IPv4 = .zero, httpPort: UInt16 = 80) {
        self.ipv4 = ipv4
        self.netmask = netmask
        self.gateway = gateway
        self.primaryDNS = primaryDNS
        self.secondaryDNS = secondaryDNS
        self.httpPort = httpPort
    }
}

/// A camera as described by its configuration announcement.
public struct Camera: Identifiable, Hashable, Sendable {
    public var id: MACAddress { mac }
    public let mac: MACAddress
    public let settings: NetworkSettings
    /// User-set camera title, e.g. "STUDIO-CAM-1". Factory default is the model name.
    public let title: String
    /// Device category: "CAM" for cameras, "RP" for remote controllers.
    public let category: String
    /// Model without the "AW-" prefix, e.g. "UE150", "HE130K", "RP120".
    public let model: String
    /// Every field from the announcement, keyed by field id. Needed to echo unknown fields back.
    public let rawFields: [UInt16: [UInt8]]
    /// Last byte of the announcement preamble (offset 57). Not documented anywhere.
    public let statusFlags: UInt8

    /// EXPERIMENTAL: whether the camera refuses Easy IP changes right now.
    ///
    /// On a rig of AW-UE150s that had been on for hours, every camera sent 0x02 here except one
    /// (00); the 2018 AW-HE130 capture, taken while changes worked, also sent 00. The assumption is
    /// that bit 1 means "Easy IP setup period expired" (20 minutes after power-on). Unconfirmed.
    public var easyIPLocked: Bool { statusFlags & 0x02 != 0 }

    public var ipv4: IPv4 { settings.ipv4 }
    public var netmask: IPv4 { settings.netmask }
    public var gateway: IPv4 { settings.gateway }
    public var httpPort: UInt16 { settings.httpPort }

    init?(mac: MACAddress, fields: [UInt16: [UInt8]], statusFlags: UInt8 = 0) {
        func ip(_ field: EasyIP.Field) -> IPv4? {
            guard let value = fields[field.rawValue], value.count == 4 else { return nil }
            return IPv4(bytes: value)
        }
        func text(_ field: EasyIP.Field) -> String {
            let value = fields[field.rawValue] ?? []
            return String(decoding: value.prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        }
        guard let ipv4 = ip(.ipv4) else { return nil }
        let dns = fields[EasyIP.Field.dns.rawValue] ?? []
        let port = fields[EasyIP.Field.httpPort.rawValue] ?? []

        self.mac = mac
        self.settings = NetworkSettings(
            ipv4: ipv4,
            netmask: ip(.netmask) ?? .zero,
            gateway: ip(.gateway) ?? .zero,
            primaryDNS: dns.count >= 4 ? IPv4(bytes: dns[0..<4]) : .zero,
            secondaryDNS: dns.count >= 8 ? IPv4(bytes: dns[4..<8]) : .zero,
            httpPort: port.count == 2 ? UInt16(port[0]) << 8 | UInt16(port[1]) : 80
        )
        self.title = text(.title)
        let categoryAndModel = text(.categoryAndModel).split(separator: ":", maxSplits: 1).map(String.init)
        self.category = categoryAndModel.count == 2 ? categoryAndModel[0] : ""
        self.model = categoryAndModel.last ?? ""
        self.rawFields = fields
        self.statusFlags = statusFlags
    }
}
