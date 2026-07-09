import Foundation
import Testing
import SignoffToolSupport

@Suite("Signoff PDK profile catalog")
struct SignoffPDKProfileCatalogTests {
    @Test func bundledCatalogSelectsDefaultProfile() throws {
        let catalog = try SignoffPDKProfileCatalog.bundled()
        let entry = try catalog.entry()
        let profile = try catalog.loadProfile()

        #expect(catalog.catalogID == "signoff.default-pdk-profiles.v1")
        #expect(entry.profileID == profile.profileID)
        #expect(entry.pdkID == profile.pdkID)
        #expect(entry.defaultProfile)
    }

    @Test func bundledDefaultProfileLoadsThroughCatalog() throws {
        let catalogProfile = try SignoffPDKProfileCatalog.loadDefaultProfile()
        let extensionProfile = try SignoffPDKProfile.bundledDefaultProfile()

        #expect(catalogProfile == extensionProfile)
    }

    @Test func selectsExplicitProfileByID() throws {
        let catalog = try SignoffPDKProfileCatalog.bundled()
        let defaultEntry = try catalog.entry()
        let selectedEntry = try catalog.entry(profileID: defaultEntry.profileID)

        #expect(selectedEntry == defaultEntry)
    }

    @Test func rejectsDuplicateProfileIDs() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "SignoffPDKProfileCatalogInvalid-\(UUID().uuidString).json")
        try Data("""
        {
          "schemaVersion": 1,
          "kind": "signoff-pdk-profile-catalog",
          "catalogID": "invalid-catalog",
          "profiles": [
            {
              "profileID": "profile-1",
              "profileResourceName": "profile-a",
              "defaultProfile": true
            },
            {
              "profileID": "profile-1",
              "profileResourceName": "profile-b"
            }
          ]
        }
        """.utf8).write(to: url)

        #expect(throws: SignoffPDKProfileCatalogError.duplicateProfileID("profile-1")) {
            _ = try SignoffPDKProfileCatalog.load(from: url)
        }
    }

    @Test func rejectsProfileIDMismatch() throws {
        let profileURL = FileManager.default.temporaryDirectory
            .appending(path: "SignoffPDKProfileCatalogProfile-\(UUID().uuidString).json")
        let catalogURL = FileManager.default.temporaryDirectory
            .appending(path: "SignoffPDKProfileCatalogMismatch-\(UUID().uuidString).json")
        try Data("""
        {
          "schemaVersion": 1,
          "profileID": "actual-profile",
          "pdkID": "customPDK",
          "rootDirectoryName": "customPDK",
          "candidateRootPaths": [],
          "requirements": [],
          "standardCellLibraries": [],
          "deckRequirements": [],
          "semanticSources": [],
          "semanticChecks": []
        }
        """.utf8).write(to: profileURL)
        try Data("""
        {
          "schemaVersion": 1,
          "kind": "signoff-pdk-profile-catalog",
          "catalogID": "mismatch-catalog",
          "profiles": [
            {
              "profileID": "declared-profile",
              "profilePath": "\(profileURL.path(percentEncoded: false))",
              "defaultProfile": true
            }
          ]
        }
        """.utf8).write(to: catalogURL)

        let catalog = try SignoffPDKProfileCatalog.load(from: catalogURL)
        #expect(throws: SignoffPDKProfileCatalogError.profileIDMismatch(
            expected: "declared-profile",
            actual: "actual-profile"
        )) {
            _ = try catalog.loadProfile()
        }
    }
}
