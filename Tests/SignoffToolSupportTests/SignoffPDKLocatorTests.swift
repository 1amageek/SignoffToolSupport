import Foundation
import Testing
import SignoffToolSupport

@Suite("Signoff PDK locator")
struct SignoffPDKLocatorTests {
    @Test func resolvesMagicRequirementFromEnvironmentRoot() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        let magicRC = root.appending(path: "sky130A/libs.tech/magic/sky130A.magicrc")
        try FileManager.default.createDirectory(
            at: magicRC.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: magicRC)

        let resolved = SignoffPDKLocator.root(
            requirementID: "magic",
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        #expect(resolved == root.path(percentEncoded: false))
    }

    @Test func resolvesMagicRequirementFromDirectSky130ARoot() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot().appending(path: "sky130A")
        let magicRC = root.appending(path: "libs.tech/magic/sky130A.magicrc")
        try FileManager.default.createDirectory(
            at: magicRC.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: magicRC)

        let resolved = SignoffPDKLocator.root(
            requirementID: "magic",
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        let expectedToolRoot = root.deletingLastPathComponent().path(percentEncoded: false)
        #expect(resolved == expectedToolRoot)
        #expect(try SignoffPDKLocator.requiredFileURL(
            in: expectedToolRoot,
            profile: profile,
            requirementID: "magic"
        ) == magicRC)
    }

    @Test func resolvesNetgenRequirementFromParentRoot() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        let setup = root.appending(path: "sky130A/libs.tech/netgen/sky130A_setup.tcl")
        try FileManager.default.createDirectory(
            at: setup.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: setup)

        let resolved = SignoffPDKLocator.root(
            requirementID: "netgen",
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        #expect(resolved == root.path(percentEncoded: false))
        #expect(try SignoffPDKLocator.requiredFileURL(
            in: root.path(percentEncoded: false),
            profile: profile,
            requirementID: "netgen"
        ) == setup)
    }

    @Test func rejectsRootMissingRequiredFile() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        let resolved = SignoffPDKLocator.root(
            requirementID: "netgen",
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        #expect(resolved == nil)
    }

    @Test func resolvesGenericProfileWithoutProcessNamedSwiftType() throws {
        let profile = try SignoffPDKProfile(
            profileID: "example.signoff",
            pdkID: "examplePDK",
            rootDirectoryName: "examplePDK",
            candidateRootPaths: [],
            requirements: [
                SignoffPDKRequiredFile(requirementID: "magic", relativePath: "tech/magic.rc")
            ],
            deckRequirements: [],
            semanticSources: [],
            semanticChecks: []
        )
        let root = try makeTemporaryRoot()
        let magicRC = root.appending(path: "examplePDK/tech/magic.rc")
        try FileManager.default.createDirectory(
            at: magicRC.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: magicRC)

        let resolved = SignoffPDKLocator.root(
            requirementID: "magic",
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        #expect(resolved == root.path(percentEncoded: false))
        #expect(try SignoffPDKLocator.requiredFileURL(
            in: root.path(percentEncoded: false),
            profile: profile,
            requirementID: "magic"
        ) == magicRC)
    }

    @Test func resolvesTemplatedStandardCellDeckRequirement() throws {
        let profile = try SignoffPDKProfile(
            profileID: "example.signoff",
            pdkID: "examplePDK",
            rootDirectoryName: "examplePDK",
            candidateRootPaths: [],
            requirements: [
                SignoffPDKRequiredFile(requirementID: "magic", relativePath: "tech/magic.rc"),
                SignoffPDKRequiredFile(
                    requirementID: "standard-cell-spice-library",
                    relativePath: "libs/{library}/{library}.spice"
                )
            ],
            standardCellLibraries: [
                SignoffPDKStandardCellLibrary(
                    libraryID: "example_std",
                    spiceDeckRequirementID: "standard-cell-spice-library"
                )
            ],
            deckRequirements: [],
            semanticSources: [],
            semanticChecks: []
        )
        let root = try makeTemporaryRoot()
        let magicRC = root.appending(path: "examplePDK/tech/magic.rc")
        let spice = root.appending(path: "examplePDK/libs/example_std/example_std.spice")
        try FileManager.default.createDirectory(
            at: magicRC.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: spice.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: magicRC)
        try Data().write(to: spice)

        let resolved = SignoffPDKLocator.root(
            requirementID: "magic",
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)]
        )

        #expect(resolved == root.path(percentEncoded: false))
        #expect(profile.standardCellLibraries.first?.libraryID == "example_std")
        #expect(try SignoffPDKLocator.requiredFileURL(
            in: root.path(percentEncoded: false),
            profile: profile,
            requirementID: "standard-cell-spice-library",
            substitutions: ["library": "example_std"]
        ) == spice)
    }

    @Test func bundledProfileDeclaresStandardCellDeckTemplateAsData() throws {
        let profile = try sky130Profile()
        let declaresStandardCellDeck = profile.standardCellLibraries.contains {
            $0.libraryID == "sky130_fd_sc_hd"
                && $0.spiceDeckRequirementID == "standard-cell-spice-library"
        }
        #expect(declaresStandardCellDeck)
        #expect(profile.requirement(withID: "standard-cell-spice-library")?.relativePath == "libs.ref/{library}/spice/{library}.spice")
    }

    @Test func rejectsUnsupportedProfileSchemaVersion() throws {
        #expect(throws: SignoffPDKProfileError.unsupportedSchemaVersion(99)) {
            _ = try SignoffPDKProfile(
                schemaVersion: 99,
                profileID: "example.signoff",
                pdkID: "examplePDK",
                rootDirectoryName: "examplePDK",
                candidateRootPaths: [],
                requirements: [],
                deckRequirements: [],
                semanticSources: [],
                semanticChecks: []
            )
        }
    }

    @Test func rejectsDuplicateRequirementIDs() throws {
        #expect(throws: SignoffPDKProfileError.duplicateRequirementID("magic")) {
            _ = try SignoffPDKProfile(
                profileID: "example.signoff",
                pdkID: "examplePDK",
                rootDirectoryName: "examplePDK",
                candidateRootPaths: [],
                requirements: [
                    SignoffPDKRequiredFile(requirementID: "magic", relativePath: "tech/magic.rc"),
                    SignoffPDKRequiredFile(requirementID: "magic", relativePath: "tech/magic2.rc"),
                ],
                deckRequirements: [],
                semanticSources: [],
                semanticChecks: []
            )
        }
    }

    @Test func rejectsUnsafeRequirementRelativePath() throws {
        #expect(throws: SignoffPDKProfileError.unsafeRelativePath(
            requirementID: "magic",
            relativePath: "../escape/magic.rc"
        )) {
            _ = try SignoffPDKProfile(
                profileID: "example.signoff",
                pdkID: "examplePDK",
                rootDirectoryName: "examplePDK",
                candidateRootPaths: [],
                requirements: [
                    SignoffPDKRequiredFile(requirementID: "magic", relativePath: "../escape/magic.rc"),
                ],
                deckRequirements: [],
                semanticSources: [],
                semanticChecks: []
            )
        }
    }

    @Test func rejectsStandardCellLibraryMissingReferencedRequirement() throws {
        #expect(throws: SignoffPDKProfileError.missingReferencedRequirement(
            field: "standardCellLibraries[0].spiceDeckRequirementID",
            requirementID: "missing-spice"
        )) {
            _ = try SignoffPDKProfile(
                profileID: "example.signoff",
                pdkID: "examplePDK",
                rootDirectoryName: "examplePDK",
                candidateRootPaths: [],
                requirements: [
                    SignoffPDKRequiredFile(requirementID: "magic", relativePath: "tech/magic.rc"),
                ],
                standardCellLibraries: [
                    SignoffPDKStandardCellLibrary(
                        libraryID: "std",
                        spiceDeckRequirementID: "missing-spice"
                    ),
                ],
                deckRequirements: [],
                semanticSources: [],
                semanticChecks: []
            )
        }
    }

    @Test func requiredFileURLRejectsUnsafeSubstitutedPath() throws {
        let profile = try SignoffPDKProfile(
            profileID: "example.signoff",
            pdkID: "examplePDK",
            rootDirectoryName: "examplePDK",
            candidateRootPaths: [],
            requirements: [
                SignoffPDKRequiredFile(
                    requirementID: "standard-cell-spice-library",
                    relativePath: "libs/{library}/{library}.spice"
                ),
            ],
            deckRequirements: [],
            semanticSources: [],
            semanticChecks: []
        )

        #expect(throws: SignoffPDKProfileError.unsafeRelativePath(
            requirementID: "standard-cell-spice-library",
            relativePath: "libs/../escape/../escape.spice"
        )) {
            _ = try SignoffPDKLocator.requiredFileURL(
                in: "/tmp/pdk",
                profile: profile,
                requirementID: "standard-cell-spice-library",
                substitutions: ["library": "../escape"]
            )
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SignoffToolSupportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sky130Profile() throws -> SignoffPDKProfile {
        try SignoffPDKProfile.bundledDefaultProfile()
    }
}
