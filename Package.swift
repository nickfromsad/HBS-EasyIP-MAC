// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HBSEasyIPMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EasyIPMac", targets: ["EasyIPMac"]),
        .executable(name: "easyip", targets: ["easyip"]),
        .library(name: "EasyIPKit", targets: ["EasyIPKit"]),
    ],
    targets: [
        // Panasonic Easy IP protocol + sockets. No UI, no dependencies.
        .target(name: "EasyIPKit"),
        // The SwiftUI app. scripts/build-app.sh wraps it into "HBS EasyIP MAC.app".
        .executableTarget(name: "EasyIPMac", dependencies: ["EasyIPKit"]),
        // Command-line version: `easyip` lists cameras, `easyip set MAC IP` changes one.
        .executableTarget(name: "easyip", dependencies: ["EasyIPKit"]),
        .testTarget(name: "EasyIPKitTests", dependencies: ["EasyIPKit"]),
    ]
)
