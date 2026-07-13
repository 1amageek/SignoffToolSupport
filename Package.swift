// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SignoffToolSupport",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SignoffToolSupport", targets: ["SignoffToolSupport"]),
    ],
    dependencies: [
        .package(path: "../CircuiteFoundation"),
    ],
    targets: [
        .target(
            name: "SignoffToolSupport",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SignoffToolSupportTests", dependencies: ["SignoffToolSupport"]),
    ]
)
