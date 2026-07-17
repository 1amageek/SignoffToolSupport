// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)

let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac"
    )

let package = Package(
    name: "SignoffToolSupport",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SignoffToolSupport", targets: ["SignoffToolSupport"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
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
