import Darwin
import Foundation
import SystemConfiguration

/// An IPv4-capable network port on this Mac, e.g. en7 "USB 10/100/1000 LAN" 10.1.0.2/24.
public struct NetworkInterface: Identifiable, Hashable, Sendable {
    public var id: String { bsdName }
    public let bsdName: String
    public let displayName: String
    public let ipv4: IPv4
    public let netmask: IPv4
    public let mac: MACAddress
    public let index: UInt32

    public var host: EasyIP.Host { EasyIP.Host(mac: mac, ipv4: ipv4) }

    public func contains(_ address: IPv4) -> Bool { address.sameSubnet(as: ipv4, mask: netmask) }

    /// Every interface that is up, broadcast-capable and has an IPv4 address.
    public static func all() -> [NetworkInterface] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var macs: [String: MACAddress] = [:]
        var candidates: [(name: String, ip: IPv4, mask: IPv4)] = []
        let required = UInt32(IFF_UP | IFF_RUNNING | IFF_BROADCAST)

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = entry.pointee
            guard let addr = ifa.ifa_addr else { continue }
            let name = String(cString: ifa.ifa_name)
            switch Int32(addr.pointee.sa_family) {
            case AF_LINK:
                addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { dl in
                    guard dl.pointee.sdl_alen == 6 else { return }
                    // sdl_data is declared as 12 bytes but really runs on: name, then address.
                    let offset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data)! + Int(dl.pointee.sdl_nlen)
                    let start = UnsafeRawPointer(dl).advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                    macs[name] = MACAddress(bytes: UnsafeBufferPointer(start: start, count: 6))
                }
            case AF_INET:
                guard ifa.ifa_flags & required == required, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                      let mask = ifa.ifa_netmask else { continue }
                candidates.append((name, ipv4(from: addr), ipv4(from: mask)))
            default:
                continue
            }
        }

        let names = displayNames()
        return candidates.map { candidate in
            NetworkInterface(
                bsdName: candidate.name,
                displayName: names[candidate.name] ?? candidate.name,
                ipv4: candidate.ip,
                netmask: candidate.mask,
                mac: macs[candidate.name] ?? .placeholder,
                index: if_nametoindex(candidate.name)
            )
        }
        .sorted { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
    }

    private static func ipv4(from sockaddr: UnsafeMutablePointer<sockaddr>) -> IPv4 {
        sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            IPv4(UInt32(bigEndian: $0.pointee.sin_addr.s_addr))
        }
    }

    /// Human readable names from System Settings ("Wi-Fi", "USB 10/100/1000 LAN", ...).
    private static func displayNames() -> [String: String] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var names: [String: String] = [:]
        for interface in interfaces {
            if let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                names[bsd] = name
            }
        }
        return names
    }
}
