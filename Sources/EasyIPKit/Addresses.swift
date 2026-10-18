import Foundation

/// An IPv4 address stored in host byte order, so it sorts and does math naturally.
public struct IPv4: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var value: UInt32

    public init(_ value: UInt32) { self.value = value }

    public init(bytes: some Collection<UInt8>) {
        precondition(bytes.count == 4)
        self.value = bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// Parses dotted-quad notation ("192.168.0.10"). Returns nil for anything else.
    public init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isASCII), let octet = UInt8(part) else { return nil }
            value = value << 8 | UInt32(octet)
        }
        self.value = value
    }

    public static let zero = IPv4(0)
    public static let broadcast = IPv4(0xFFFF_FFFF)

    public var bytes: [UInt8] {
        [UInt8(value >> 24), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    public var description: String { bytes.map(String.init).joined(separator: ".") }

    public func sameSubnet(as other: IPv4, mask: IPv4) -> Bool {
        value & mask.value == other.value & mask.value
    }

    /// Number of leading one-bits, e.g. 255.255.255.0 -> 24.
    public var prefixLength: Int { value.leadingZeroBitCount == 0 ? (~value).leadingZeroBitCount : 0 }

    public static func < (lhs: IPv4, rhs: IPv4) -> Bool { lhs.value < rhs.value }
}

public struct MACAddress: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init(bytes: some Collection<UInt8>) {
        precondition(bytes.count == 6)
        self.bytes = Array(bytes)
    }

    /// Locally administered placeholder, used when an interface has no hardware address.
    public static let placeholder = MACAddress(bytes: [0x02, 0, 0, 0, 0, 0])

    public var description: String { bytes.map { String(format: "%02X", $0) }.joined(separator: ":") }

    public static func < (lhs: MACAddress, rhs: MACAddress) -> Bool { lhs.bytes.lexicographicallyPrecedes(rhs.bytes) }
}
