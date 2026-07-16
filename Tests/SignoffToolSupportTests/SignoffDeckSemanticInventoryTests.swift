import Foundation
import Testing
import SignoffToolSupport

@Suite("Signoff deck semantic inventory")
struct SignoffDeckSemanticInventoryTests {
    @Test func reportsFoundryDeckSemanticCoverage() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFoundryDecks(root: root)

        let report = SignoffDeckSemanticInventory.inspect(
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-23T00:00:00Z"
        )

        #expect(report.kind == "signoff-foundry-deck-semantics")
        #expect(report.generatedAt == "2026-06-23T00:00:00Z")
        #expect(report.status == .passed)
        #expect(report.failures.isEmpty)
        #expect(report.magicDRC?.ruleFamilyCounts["width"] == 1)
        #expect(report.magicDRC?.ruleFamilyCounts["spacing"] == 1)
        #expect(report.magicDRC?.ruleFamilyCounts["notch"] == 1)
        #expect(report.magicDRC?.ruleFamilyCounts["rect_only"] == 1)
        #expect(report.magicDRC?.ruleFamilyCounts["surround"] == 1)
        #expect(report.magicDRC?.ruleFamilyCounts["overhang"] == 1)
        #expect(report.magicDRC?.ruleFamilyCounts["area"] == 1)
        #expect(report.magicDRC?.ruleFamilyCounts["widespacing"] == 1)
        #expect(report.magicDRC?.cutClassCount == 1)
        #expect(report.magicDRC?.contactStackCount == 1)
        #expect(report.magicDRC?.wiringContactCount == 1)
        #expect(report.magicDRC?.exactOverlapCount == 1)
        #expect(report.magicDRC?.enclosedHoleCount == 1)
        #expect(report.netgenLVS?.deviceFamilyCounts["mos"] == 1)
        #expect(report.netgenLVS?.deviceFamilyCounts["resistor"] == 1)
        #expect(report.netgenLVS?.deviceFamilyCounts["diode"] == 1)
        #expect(report.netgenLVS?.deviceFamilyCounts["capacitor"] == 1)
        #expect(report.netgenLVS?.deviceFamilyCounts["bjt"] == 1)
        #expect(report.netgenLVS?.deviceFamilyCounts["inductor"] == 1)
        let contactGeometry = try #require(report.coverageTagResults.first { $0.tag == "drc.deck.contact-geometry" })
        #expect(contactGeometry.evidenceCount == 2)
        #expect(report.coverageTagResults.allSatisfy { $0.status == .passed })
    }

    @Test func blocksMissingNetgenPinPolicy() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFoundryDecks(root: root, includeNetgenPolicies: false)

        let report = SignoffDeckSemanticInventory.inspect(
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-23T00:00:00Z"
        )

        #expect(report.status == .blocked)
        let pinMap = try #require(report.coverageTagResults.first { $0.tag == "lvs.deck.pin-map" })
        #expect(pinMap.status == .blocked)
        #expect(pinMap.diagnostics.contains { $0.code == "netgen_pin_policy_missing" })
        #expect(report.failures.contains { $0.coverageTag == "lvs.deck.pin-map" })
    }

    @Test func rejectsMissingSemanticSourceRequirementInProfileValidation() throws {
        let profile = try sky130Profile()

        #expect(throws: SignoffPDKProfileError.missingReferencedRequirement(
            field: "semanticSources[2].requirementID",
            requirementID: "missing-netgen-setup"
        )) {
            _ = try SignoffPDKProfile(
                schemaVersion: profile.schemaVersion,
                profileID: profile.profileID,
                pdkID: profile.pdkID,
                rootDirectoryName: profile.rootDirectoryName,
                candidateRootPaths: profile.candidateRootPaths,
                requirements: profile.requirements,
                standardCellLibraries: profile.standardCellLibraries,
                deckRequirements: profile.deckRequirements,
                semanticSources: profile.semanticSources.map {
                    guard $0.role == "netgen-setup" else {
                        return $0
                    }
                    return SignoffDeckSemanticSourceRequirement(
                        requirementID: "missing-netgen-setup",
                        role: $0.role
                    )
                },
                semanticChecks: profile.semanticChecks
            )
        }
    }

    @Test func reportsDRCDomainWithoutNetgenRequirement() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFoundryDecks(root: root, includeNetgenDeck: false)

        let report = SignoffDeckSemanticInventory.inspect(
            profile: profile,
            requirements: profile.deckRequirements(domain: "drc", backendID: "magic"),
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-23T00:00:00Z"
        )

        #expect(report.status == .passed)
        #expect(report.netgenLVS == nil)
        #expect(report.sources.allSatisfy { $0.role != "netgen-setup" })
        #expect(report.coverageTagResults.map(\.tag) == [
            "drc.deck.sky130",
            "drc.deck.rule-table",
            "drc.deck.cut-classes",
            "drc.deck.contact-geometry",
            "drc.deck.exact-overlap",
            "drc.deck.enclosed-hole",
            "drc.deck.unit-scaling",
        ])
        #expect(report.failures.isEmpty)
    }

    @Test func contactStackSatisfiesDRCContactGeometryCoverageWithoutWiringContact() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFoundryDecks(root: root, includeNetgenDeck: false, includeWiringContact: false)

        let report = SignoffDeckSemanticInventory.inspect(
            profile: profile,
            requirements: profile.deckRequirements(domain: "drc", backendID: "magic"),
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-25T00:00:00Z"
        )

        let contactGeometry = try #require(report.coverageTagResults.first { $0.tag == "drc.deck.contact-geometry" })
        #expect(report.status == .passed)
        #expect(report.magicDRC?.contactStackCount == 1)
        #expect(report.magicDRC?.wiringContactCount == 0)
        #expect(contactGeometry.status == .passed)
        #expect(contactGeometry.evidenceCount == 1)
    }

    @Test func encodesStableJSONContract() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFoundryDecks(root: root)
        let report = SignoffDeckSemanticInventory.inspect(
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-23T00:00:00Z"
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(SignoffDeckSemanticReport.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.kind == "signoff-foundry-deck-semantics")
        #expect(decoded.generatedAt == "2026-06-23T00:00:00Z")
        #expect(decoded.sources.count == 3)
        #expect(decoded.coverageTagResults.count == 10)
        #expect(decoded.failures.isEmpty)
    }

    @Test func rejectsUnsupportedReportSchema() throws {
        let report = SignoffDeckSemanticReport(
            schemaVersion: 2,
            generatedAt: "2026-06-23T00:00:00Z",
            status: .passed,
            pdkRoot: nil,
            sources: [],
            magicDRC: nil,
            netgenLVS: nil,
            coverageTagResults: [],
            failures: []
        )
        let data = try JSONEncoder().encode(report)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SignoffDeckSemanticReport.self, from: data)
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SignoffDeckSemanticInventoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sky130Profile() throws -> SignoffPDKProfile {
        try SignoffPDKProfile.bundledDefaultProfile()
    }

    private func writeFoundryDecks(
        root: URL,
        includeNetgenDeck: Bool = true,
        includeNetgenPolicies: Bool = true,
        includeWiringContact: Bool = true
    ) throws {
        let wiringContactSection = includeWiringContact
            ? """
            wiring
              contact v1 150 met1 0 30 met2 0 40
            end
            """
            : ""
        try writeFile(
            root.appending(path: "sky130A/libs.tech/magic/sky130A.magicrc"),
            """
            set scalefac [tech lambda]
            scalegrid 1 2
            tech load $PDK_ROOT/sky130A/libs.tech/magic/sky130A.tech
            snap lambda
            """
        )
        try writeFile(
            root.appending(path: "sky130A/libs.tech/magic/sky130A.tech"),
            """
            tech
              sky130A
            end
            cifoutput
              templayer m1_small_hole met1
                close 140000
              templayer m1_hole_empty m1_small_hole
                and-not met1
              cifmaxwidth m1_hole_empty 0 83000 "Metal1 enclosed hole"
            end
            drc
              width met1 140 "Metal1 width"
              spacing met1 met1 140 touching_ok "Metal1 spacing"
              notch met1 280 "Metal1 notch"
              surround via1 met1 30 directional "Metal1 surround"
              overhang poly nfet 130 "Gate overhang"
              area met1 83000 140 "Metal1 area"
              widespacing met1 3000 met1 900 touching_ok "Metal1 wide spacing"
              rect_only met1 "Metal1 rectangular only"
              exact_overlap v1/m1
            end
            cut m2c via via1 VIA1 v1
            contact
              via1 met1 met2
            end
            \(wiringContactSection)
            extract
              device mosfet sky130_fd_pr__nfet_01v8 nfet ndiff
            end
            """
        )
        guard includeNetgenDeck else {
            return
        }
        let policies = includeNetgenPolicies
            ? """
              permute "-circuit1 $dev" 1 2
              property "-circuit1 $dev" parallel enable
              equate pins "-circuit1 $dev" "-circuit2 $dev"
              """
            : ""
        try writeFile(
            root.appending(path: "sky130A/libs.tech/netgen/sky130A_setup.tcl"),
            """
            lappend devices sky130_fd_pr__nfet_01v8
            lappend devices sky130_fd_pr__res_generic_m1
            lappend devices sky130_fd_pr__diode_pw2nd_05v5
            lappend devices sky130_fd_pr__cap_mim_m3_1
            lappend devices sky130_fd_pr__npn_05v5
            lappend devices sky130_fd_pr__ind_04_01
            \(policies)
            """
        )
    }

    private func writeFile(_ url: URL, _ text: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
