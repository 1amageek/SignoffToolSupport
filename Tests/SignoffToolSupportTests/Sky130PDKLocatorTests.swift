import Foundation
import Testing
import SignoffToolSupport

@Suite("Sky130 PDK locator")
struct Sky130PDKLocatorTests {
    @Test func resolvesMagicRequirementFromEnvironmentRoot() throws {
        let root = try makeTemporaryRoot()
        let magicRC = root.appending(path: "sky130A/libs.tech/magic/sky130A.magicrc")
        try FileManager.default.createDirectory(
            at: magicRC.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: magicRC)

        let resolved = Sky130PDKLocator.root(
            requirement: .magic,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        #expect(resolved == root.path(percentEncoded: false))
    }

    @Test func rejectsRootMissingRequiredFile() throws {
        let root = try makeTemporaryRoot()
        let resolved = Sky130PDKLocator.root(
            requirement: .netgen,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        #expect(resolved == nil)
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SignoffToolSupportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
