import AppKit
import EasyIPKit
import Foundation

/// An extra IPv4 address on one of the Mac's network ports, so the Mac can talk to cameras in
/// another subnet without changing anything on the cameras. Same as
/// `sudo ifconfig en8 alias 172.17.100.250 netmask 255.255.255.0`.
struct SubnetAlias: Codable, Hashable, Identifiable {
    var id: String { "\(bsdName)/\(address)" }
    let bsdName: String
    let addressValue: UInt32
    let netmaskValue: UInt32

    var address: IPv4 { IPv4(addressValue) }
    var netmask: IPv4 { IPv4(netmaskValue) }

    init(bsdName: String, address: IPv4, netmask: IPv4) {
        self.bsdName = bsdName
        self.addressValue = address.value
        self.netmaskValue = netmask.value
    }

    /// Interface names come from getifaddrs and addresses from IPv4, but they end up in a root shell
    /// command, so they are validated again here.
    private var isSafe: Bool {
        !bsdName.isEmpty && bsdName.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    fileprivate var addCommand: String {
        "/sbin/ifconfig \(bsdName) alias \(address) netmask \(netmask)"
    }

    fileprivate var removeCommand: String {
        "/sbin/ifconfig \(bsdName) -alias \(address)"
    }

    enum Failure: LocalizedError {
        case invalid
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .invalid: "Invalid network port or address."
            case .cancelled: "Cancelled. No IP address was added or removed."
            case let .failed(message): message
            }
        }
    }

    static func add(_ alias: SubnetAlias) throws {
        guard alias.isSafe else { throw Failure.invalid }
        try runAsAdministrator([alias.addCommand])
    }

    /// Removes several aliases with a single password prompt.
    static func remove(_ aliases: [SubnetAlias]) throws {
        let safe = aliases.filter(\.isSafe)
        guard !safe.isEmpty else { return }
        // `; true`: one alias already gone (cable unplugged) must not stop the others.
        try runAsAdministrator(safe.map { $0.removeCommand + " ; true" })
    }

    /// Asks for the administrator password with the standard macOS dialog and runs the commands as root.
    private static func runAsAdministrator(_ commands: [String]) throws {
        let shell = commands.joined(separator: " ; ")
        let source = "do shell script \"\(shell)\" with prompt \"EasyIP MAC wants to change the IP addresses of this Mac.\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { throw Failure.cancelled }
        throw Failure.failed(error[NSAppleScript.errorMessage] as? String ?? "Changing the IP address failed.")
    }
}
