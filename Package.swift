// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SignoffToolSupport",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SignoffToolSupport", targets: ["SignoffToolSupport"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SignoffToolSupport",
            dependencies: [],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SignoffToolSupportTests", dependencies: ["SignoffToolSupport"]),
    ]
)
