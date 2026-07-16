import Foundation
import Testing
import SignoffToolSupport

@Suite("Signoff deck inventory")
struct SignoffDeckInventoryTests {
    @Test func reportsReadyMagicAndNetgenDecks() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFile(root.appending(path: "sky130A/libs.tech/magic/sky130A.magicrc"))
        try writeFile(root.appending(path: "sky130A/libs.tech/netgen/sky130A_setup.tcl"))

        let report = SignoffDeckInventory.inspect(
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-23T00:00:00Z"
        )

        #expect(report.kind == "signoff-foundry-deck-readiness")
        #expect(report.generatedAt == "2026-06-23T00:00:00Z")
        #expect(report.status == .passed)
        #expect(report.checkedDeckCount == 2)
        #expect(report.passedDeckCount == 2)
        #expect(report.blockedDeckCount == 0)
        #expect(report.failures.isEmpty)
        #expect(report.results.contains { result in
            result.deckID == "sky130.magic.drc"
                && result.domain == "drc"
                && result.backendID == "magic"
                && result.requiredCoverageTags.contains("drc.deck.sky130")
                && result.requiredCoverageTags.contains("drc.deck.cut-classes")
                && result.requiredCoverageTags.contains("drc.deck.contact-geometry")
                && result.requiredCoverageTags.contains("drc.deck.exact-overlap")
                && result.requiredFileExists
        })
        #expect(report.results.contains { result in
            result.deckID == "sky130.netgen.lvs"
                && result.domain == "lvs"
                && result.backendID == "netgen"
                && result.requiredCoverageTags.contains("lvs.deck.sky130")
                && result.requiredFileExists
        })
    }

    @Test func blocksMissingNetgenDeckWithoutFailingMagicDeck() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFile(root.appending(path: "sky130A/libs.tech/magic/sky130A.magicrc"))

        let report = SignoffDeckInventory.inspect(
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-23T00:00:00Z"
        )

        #expect(report.status == .blocked)
        #expect(report.passedDeckCount == 1)
        #expect(report.blockedDeckCount == 1)
        #expect(report.failures.count == 1)

        let lvs = try #require(report.results.first { $0.deckID == "sky130.netgen.lvs" })
        #expect(lvs.status == .blocked)
        #expect(lvs.diagnostics.contains { $0.code == "missing_pdk_required_file" })

        let failure = try #require(report.failures.first)
        #expect(failure.code == "signoff_foundry_deck_blocked")
        #expect(failure.deckID == "sky130.netgen.lvs")
        #expect(failure.domain == "lvs")
        #expect(failure.backendID == "netgen")
        #expect(failure.diagnostics.contains { $0.code == "missing_pdk_required_file" })
    }

    @Test func encodesStableJSONContract() throws {
        let profile = try sky130Profile()
        let root = try makeTemporaryRoot()
        try writeFile(root.appending(path: "sky130A/libs.tech/magic/sky130A.magicrc"))
        try writeFile(root.appending(path: "sky130A/libs.tech/netgen/sky130A_setup.tcl"))
        let report = SignoffDeckInventory.inspect(
            profile: profile,
            environment: ["PDK_ROOT": root.path(percentEncoded: false)],
            generatedAt: "2026-06-23T00:00:00Z"
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(SignoffDeckInventoryReport.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.kind == "signoff-foundry-deck-readiness")
        #expect(decoded.generatedAt == "2026-06-23T00:00:00Z")
        #expect(decoded.results.count == 2)
        #expect(decoded.failures.isEmpty)
    }

    @Test func rejectsUnsupportedReportSchema() throws {
        let report = SignoffDeckInventoryReport(
            schemaVersion: 2,
            generatedAt: "2026-06-23T00:00:00Z",
            status: .passed,
            checkedDeckCount: 0,
            passedDeckCount: 0,
            blockedDeckCount: 0,
            results: [],
            failures: []
        )
        let data = try JSONEncoder().encode(report)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SignoffDeckInventoryReport.self, from: data)
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SignoffDeckInventoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sky130Profile() throws -> SignoffPDKProfile {
        try SignoffPDKProfile.bundledDefaultProfile()
    }

    private func writeFile(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: url)
    }
}
