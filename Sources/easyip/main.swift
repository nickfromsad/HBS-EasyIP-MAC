import EasyIPKit
import Foundation

let usage = """
usage: easyip [--time SECONDS]
       easyip set MAC IP [--mask MASK] [--gateway IP] [--port PORT] [--dns IP] [--dns2 IP]

Finds Panasonic PTZ cameras with Easy IP, in any subnet on the local network.
`set` changes the network settings of the camera with that MAC address
(only within 20 minutes of power-on, unless the camera allows it longer).
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func require<T>(_ value: T?, _ message: @autoclosure () -> String) -> T {
    guard let value else { fail(message()) }
    return value
}

func pad(_ string: String, _ width: Int) -> String {
    string.padding(toLength: max(width, string.count + 1), withPad: " ", startingAt: 0)
}

@MainActor
func run() async {
    var args = Array(CommandLine.arguments.dropFirst())
    var options: [String: String] = [:]
    while let index = args.firstIndex(where: { $0.hasPrefix("--") }) {
        let key = String(args.remove(at: index).dropFirst(2))
        if key == "help" { print(usage); exit(0) }
        guard index < args.count else { fail("missing value for --\(key)\n\n\(usage)") }
        options[key] = args.remove(at: index)
    }
    func address(_ key: String) -> IPv4? {
        options[key].map { require(IPv4($0), "invalid address for --\(key): \($0)") }
    }

    let client: EasyIPClient
    do { client = try EasyIPClient() } catch { fail(error.localizedDescription) }
    var cameras: [MACAddress: Camera] = [:]
    client.onCamera = { cameras[$0.mac] = $0 }

    let seconds = options["time"].map { require(Double($0), "invalid --time") } ?? 3
    do {
        try await client.search(duration: .seconds(seconds))
    } catch {
        fail(error.localizedDescription)
    }

    switch args.first {
    case nil:
        for interface in client.interfaces {
            print("searched on \(interface.bsdName) (\(interface.displayName)) \(interface.ipv4)/\(interface.netmask.prefixLength)")
        }
        print()
        print(pad("IP", 16) + pad("Title", 16) + pad("Model", 9) + pad("Type", 5) + pad("MAC", 19) + pad("Mask", 16) + pad("Gateway", 16) + "Port")
        for camera in cameras.values.sorted(by: { $0.ipv4 < $1.ipv4 }) {
            let reachable = client.interfaces.contains { $0.contains(camera.ipv4) }
            print(pad(camera.ipv4.description, 16) + pad(camera.title, 16) + pad(camera.model, 9)
                + pad(camera.category, 5) + pad(camera.mac.description, 19) + pad(camera.netmask.description, 16)
                + pad(camera.gateway.description, 16) + pad(String(camera.httpPort), 5)
                + (reachable ? "" : "(other subnet)"))
        }
        print("\n\(cameras.count) camera(s) found")

    case "set":
        guard args.count == 3, let ip = IPv4(args[2]) else { fail(usage) }
        let mac = args[1].uppercased().replacingOccurrences(of: "-", with: ":")
        guard let camera = cameras.values.first(where: { $0.mac.description == mac }) else {
            fail("No camera with MAC \(mac) answered the search.")
        }
        var settings = camera.settings
        settings.ipv4 = ip
        settings.netmask = address("mask") ?? settings.netmask
        settings.gateway = address("gateway") ?? settings.gateway
        settings.primaryDNS = address("dns") ?? settings.primaryDNS
        settings.secondaryDNS = address("dns2") ?? settings.secondaryDNS
        if let port = options["port"] { settings.httpPort = require(UInt16(port), "invalid --port") }

        print("Setting \(camera.title) (\(camera.model), \(camera.mac)): \(camera.ipv4) → \(settings.ipv4)/\(settings.netmask.prefixLength) gw \(settings.gateway)")
        do {
            try await client.reconfigure(camera, to: settings)
            print("OK, camera accepted the new settings.")
        } catch {
            fail(error.localizedDescription)
        }

    default:
        fail(usage)
    }
}

await run()
