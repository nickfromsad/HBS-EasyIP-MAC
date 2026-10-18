// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DomeScanner",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DomeScanner", targets: ["DomeScanner"]),
        .executable(name: "domescan", targets: ["domescan"]),
        .library(name: "EasyIPKit", targets: ["EasyIPKit"]),
    ],
    targets: [
        // Panasonic Easy IP protocol + sockets. No UI, no dependencies.
        .target(name: "EasyIPKit"),
        // The SwiftUI app. scripts/build-app.sh wraps it into "Dome Scanner.app".
        .executableTarget(name: "DomeScanner", dependencies: ["EasyIPKit"]),
        // Command-line version: `domescan` lists cameras, `domescan set MAC IP` changes one.
        .executableTarget(name: "domescan", dependencies: ["EasyIPKit"]),
        .testTarget(name: "EasyIPKitTests", dependencies: ["EasyIPKit"]),
    ]
)
