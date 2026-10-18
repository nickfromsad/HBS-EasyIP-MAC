import Testing
@testable import EasyIPKit

// Fixtures are real packets captured from Panasonic's Windows "Easy IP Setup" tool talking to an
// AW-HE130 (captures published by dPro-Software/PanasonicEasyIPsetupCore, 2018).

private func hex(_ string: String) -> [UInt8] {
    let clean = string.filter(\.isHexDigit)
    return stride(from: 0, to: clean.count, by: 2).map {
        let start = clean.index(clean.startIndex, offsetBy: $0)
        return UInt8(clean[start...clean.index(after: start)], radix: 16)!
    }
}

private enum Capture {
    static let windowsHost = EasyIP.Host(mac: MACAddress(bytes: hex("001C424BBBF8")), ipv4: IPv4("10.1.0.53")!)

    static let search = hex("""
    0001002A000D000000000000001C424BBBF8A9FEE00E000020111E11231F1E1913000000010000000000000000000000\
    FFF00026002000210022002300250028004000410042004400A500A600A700A800AD00B300B400B700B8FFFF1221
    """)

    static let announcement = hex("""
    00:01:01:75:00:0e:a8:13:74:76:a8:6b:00:1c:42:4b:bb:f8:a9:fe:e0:0e:00:00:20:11:1e:11:23:1f:1e:19:13:00:00:02:02:00:00:00:00:00:00:00:00:00:00:00:00:00:00:01:02:00:01:00:01:00:00:20:00:04:c0:a8:00:0a:00:21:00:04:ff:ff:ff:00:00:22:00:04:c0:a8:00:01:00:23:00:08:00:00:00:00:00:00:00:00:00:25:00:02:00:50:00:40:00:10:fe:80:00:00:00:00:00:00:aa:13:74:ff:fe:76:a8:6b:00:41:00:10:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:42:00:20:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:44:00:02:00:50:00:45:00:02:00:40:00:a0:00:04:c0:a8:00:0a:00:a1:00:04:ff:ff:ff:00:00:a2:00:04:c0:a8:00:01:00:a3:00:08:00:00:00:00:00:00:00:00:00:a4:00:04:7f:ff:ff:ff:00:a6:00:01:92:00:a7:00:10:41:57:2d:48:45:31:33:30:00:00:00:00:00:00:00:00:00:a8:00:10:43:41:4d:3a:48:45:31:33:30:4b:00:00:00:00:00:00:00:a9:00:10:30:32:2e:30:30:30:30:00:00:00:00:00:00:00:00:00:00:aa:00:10:30:2e:30:30:00:00:00:00:00:00:00:00:00:00:00:00:00:b1:00:28:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:b2:00:28:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:b4:00:02:00:00:00:b5:00:01:00:00:b6:00:01:92:ff:ff:35:e4
    """)

    /// Windows tool setting the camera to 10.1.0.216/24, gw 10.1.0.1, DNS 10.1.0.250 + .251.
    static let reconfigure = hex("""
    000100af0002a8137476a86b001c424bbbf80a010035000120111e11231f1e191300000202000000000000000000000000\
    000001030001000100002000040a0100d800210004ffffff00002200040a010001002300080a0100fa0a0100fb00250002\
    005000400010fe80000000000000aa1374fffe76a86b00410010000000000000000000000000000000000042002000000000\
    0000000000000000000000000000000000000000000000000000000000440002005000a000040a0100d800a10004ffffff00\
    00a200040a01000100a300080a0100fa0a0100fb00a6000192ffff219c
    """)

    /// A real AW-UE150 captured in 2026, anonymised: MAC, IP, gateway and title replaced.
    static let ue150 = hex("""
    00010175000e0080456a1b2c020000000000c0a80014000020111e11231f1e19130000020000000000000000000000000000\
    000102000100010200200004c0a8000a00210004ffffff0000220004c0a80001002300080000000000000000002500020050\
    00400010fe80000000000000028045fffe6a1b2c004100100000000000000000000000000000000000420020000000000000\
    000000000000000000000000000000000000000000000000000000440002005000450002008000a00004c0a8000a00a10004\
    ffffff0000a20004c0a8000100a30008000000000000000000a400047fffffff00a600019200a7001053545544494f2d4341\
    4d2d310000000000a8001043414d3a55453135300000000000000000a900100100000000000000000000000000000000aa00\
    100000000000000000000000000000000000b100280000000000000000000000000000000000000000000000000000000000\
    000000000000000000000000b200280000000000000000000000000000000000000000000000000000000000000000000000\
    000000000000b40002000100b500010000b6000192ffff2f33
    """)

    static let ack = hex("000100000003a8137476a86b001c424bbbf80a010035000120111e11231f1e1913000002020000000000000000000000ffff0848")
    static let commit = hex("000100000004a8137476a86b001c424bbbf80a010035000220111e11231f1e1913000002020000000000000000000000ffff084a")
}

@Test func searchRequestMatchesWindowsTool() {
    let host = EasyIP.Host(mac: MACAddress(bytes: hex("001C424BBBF8")), ipv4: IPv4("169.254.224.14")!)
    #expect(EasyIP.searchRequest(from: host) == Capture.search)
}

@Test func parsesHE130Announcement() throws {
    guard case let .announcement(camera) = EasyIP.parse(Capture.announcement) else {
        Issue.record("announcement not recognised")
        return
    }
    #expect(camera.mac.description == "A8:13:74:76:A8:6B")
    #expect(camera.ipv4 == IPv4("192.168.0.10"))
    #expect(camera.netmask == IPv4("255.255.255.0"))
    #expect(camera.gateway == IPv4("192.168.0.1"))
    #expect(camera.httpPort == 80)
    #expect(camera.title == "AW-HE130")
    #expect(camera.category == "CAM")
    #expect(camera.model == "HE130K")
    // Captured while the Windows tool could still change it.
    #expect(!camera.easyIPLocked)
}

@Test func parsesUE150Announcement() throws {
    guard case let .announcement(camera) = EasyIP.parse(Capture.ue150) else {
        Issue.record("announcement not recognised")
        return
    }
    #expect(camera.mac.description == "00:80:45:6A:1B:2C")
    #expect(camera.ipv4 == IPv4("192.168.0.10"))
    #expect(camera.netmask == IPv4("255.255.255.0"))
    #expect(camera.title == "STUDIO-CAM-1")
    #expect(camera.category == "CAM")
    #expect(camera.model == "UE150")
    #expect(camera.httpPort == 80)
    // Captured hours after power-on.
    #expect(camera.statusFlags == 0x02)
    #expect(camera.easyIPLocked)
}

@Test func reconfigureRequestMatchesWindowsTool() throws {
    guard case let .announcement(camera) = EasyIP.parse(Capture.announcement) else {
        Issue.record("announcement not recognised")
        return
    }
    let settings = NetworkSettings(
        ipv4: IPv4("10.1.0.216")!, netmask: IPv4("255.255.255.0")!, gateway: IPv4("10.1.0.1")!,
        primaryDNS: IPv4("10.1.0.250")!, secondaryDNS: IPv4("10.1.0.251")!, httpPort: 80
    )
    #expect(EasyIP.reconfigureRequest(for: camera, settings: settings, from: Capture.windowsHost) == Capture.reconfigure)
}

@Test func parsesAckAndBuildsMatchingCommit() {
    let camera = MACAddress(bytes: hex("a8137476a86b"))
    #expect(EasyIP.parse(Capture.ack) == .reconfigureAck(camera: camera, host: Capture.windowsHost))
    #expect(EasyIP.reconfigureCommit(for: camera, from: Capture.windowsHost) == Capture.commit)
}

@Test func rejectsCorruptPackets() {
    var corrupt = Capture.announcement
    corrupt[70] ^= 0xFF
    #expect(EasyIP.parse(corrupt) == nil)
    #expect(EasyIP.parse(Array(Capture.announcement.dropLast(5))) == nil)
    #expect(EasyIP.parse([]) == nil)
    // Our own search request must not be mistaken for a camera.
    #expect(EasyIP.parse(Capture.search) == nil)
}

@Test func ipv4Parsing() {
    #expect(IPv4("192.168.0.10")?.description == "192.168.0.10")
    #expect(IPv4("256.1.1.1") == nil)
    #expect(IPv4("1.2.3") == nil)
    #expect(IPv4("1.2.3.4.5") == nil)
    #expect(IPv4("a.b.c.d") == nil)
    #expect(IPv4("255.255.255.0")!.prefixLength == 24)
    #expect(IPv4("10.1.0.20")!.sameSubnet(as: IPv4("10.1.0.200")!, mask: IPv4("255.255.255.0")!))
    #expect(!IPv4("10.1.1.20")!.sameSubnet(as: IPv4("10.1.0.200")!, mask: IPv4("255.255.255.0")!))
}
