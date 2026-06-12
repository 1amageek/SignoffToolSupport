// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SignoffToolSupport",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SignoffToolSupport", targets: ["SignoffToolSupport"]),
    ],
    targets: [
        .target(name: "SignoffToolSupport"),
        .testTarget(name: "SignoffToolSupportTests", dependencies: ["SignoffToolSupport"]),
    ]
)
