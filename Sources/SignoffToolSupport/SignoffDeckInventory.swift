import Foundation

public enum SignoffDeckStatus: String, Codable, Sendable, Hashable {
    case passed
    case blocked
}

public struct SignoffDeckDiagnostic: Codable, Sendable, Hashable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public struct SignoffDeckRequirement: Codable, Sendable, Hashable {
    public let deckID: String
    public let domain: String
    public let backendID: String
    public let pdkRequirement: String
    public let requiredCoverageTags: [String]

    public init(
        deckID: String,
        domain: String,
        backendID: String,
        pdkRequirement: String,
        requiredCoverageTags: [String]
    ) {
        self.deckID = deckID
        self.domain = domain
        self.backendID = backendID
        self.pdkRequirement = pdkRequirement
        self.requiredCoverageTags = requiredCoverageTags
    }
}

public struct SignoffDeckResult: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let deckID: String
    public let domain: String
    public let backendID: String
    public let pdkRequirement: String
    public let status: SignoffDeckStatus
    public let pdkRoot: String?
    public let requiredFile: String?
    public let requiredFileExists: Bool
    public let requiredCoverageTags: [String]
    public let diagnostics: [SignoffDeckDiagnostic]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        deckID: String,
        domain: String,
        backendID: String,
        pdkRequirement: String,
        status: SignoffDeckStatus,
        pdkRoot: String?,
        requiredFile: String?,
        requiredFileExists: Bool,
        requiredCoverageTags: [String],
        diagnostics: [SignoffDeckDiagnostic]
    ) {
        self.schemaVersion = schemaVersion
        self.deckID = deckID
        self.domain = domain
        self.backendID = backendID
        self.pdkRequirement = pdkRequirement
        self.status = status
        self.pdkRoot = pdkRoot
        self.requiredFile = requiredFile
        self.requiredFileExists = requiredFileExists
        self.requiredCoverageTags = requiredCoverageTags
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, deckID, domain, backendID, pdkRequirement, status
        case pdkRoot, requiredFile, requiredFileExists, requiredCoverageTags, diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported signoff deck result schema version \(schemaVersion)."
            )
        }
        self.schemaVersion = schemaVersion
        deckID = try container.decode(String.self, forKey: .deckID)
        domain = try container.decode(String.self, forKey: .domain)
        backendID = try container.decode(String.self, forKey: .backendID)
        pdkRequirement = try container.decode(String.self, forKey: .pdkRequirement)
        status = try container.decode(SignoffDeckStatus.self, forKey: .status)
        pdkRoot = try container.decodeIfPresent(String.self, forKey: .pdkRoot)
        requiredFile = try container.decodeIfPresent(String.self, forKey: .requiredFile)
        requiredFileExists = try container.decode(Bool.self, forKey: .requiredFileExists)
        requiredCoverageTags = try container.decode([String].self, forKey: .requiredCoverageTags)
        diagnostics = try container.decode([SignoffDeckDiagnostic].self, forKey: .diagnostics)
    }
}

public struct SignoffDeckFailure: Codable, Sendable, Hashable {
    public let code: String
    public let deckID: String
    public let domain: String
    public let backendID: String
    public let diagnostics: [SignoffDeckDiagnostic]

    public init(
        code: String,
        deckID: String,
        domain: String,
        backendID: String,
        diagnostics: [SignoffDeckDiagnostic]
    ) {
        self.code = code
        self.deckID = deckID
        self.domain = domain
        self.backendID = backendID
        self.diagnostics = diagnostics
    }
}

public struct SignoffDeckInventoryReport: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let kind: String
    public let generatedAt: String
    public let status: SignoffDeckStatus
    public let checkedDeckCount: Int
    public let passedDeckCount: Int
    public let blockedDeckCount: Int
    public let results: [SignoffDeckResult]
    public let failures: [SignoffDeckFailure]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = "signoff-foundry-deck-readiness",
        generatedAt: String,
        status: SignoffDeckStatus,
        checkedDeckCount: Int,
        passedDeckCount: Int,
        blockedDeckCount: Int,
        results: [SignoffDeckResult],
        failures: [SignoffDeckFailure]
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.generatedAt = generatedAt
        self.status = status
        self.checkedDeckCount = checkedDeckCount
        self.passedDeckCount = passedDeckCount
        self.blockedDeckCount = blockedDeckCount
        self.results = results
        self.failures = failures
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, generatedAt, status, checkedDeckCount
        case passedDeckCount, blockedDeckCount, results, failures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported signoff deck inventory schema version \(schemaVersion)."
            )
        }
        self.schemaVersion = schemaVersion
        kind = try container.decode(String.self, forKey: .kind)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        status = try container.decode(SignoffDeckStatus.self, forKey: .status)
        checkedDeckCount = try container.decode(Int.self, forKey: .checkedDeckCount)
        passedDeckCount = try container.decode(Int.self, forKey: .passedDeckCount)
        blockedDeckCount = try container.decode(Int.self, forKey: .blockedDeckCount)
        results = try container.decode([SignoffDeckResult].self, forKey: .results)
        failures = try container.decode([SignoffDeckFailure].self, forKey: .failures)
    }
}

public enum SignoffDeckInventory {
    public static func inspect(
        profile: SignoffPDKProfile,
        requirements: [SignoffDeckRequirement]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        generatedAt: String? = nil
    ) -> SignoffDeckInventoryReport {
        let activeRequirements = requirements ?? profile.deckRequirements
        let results = activeRequirements.map {
            inspect(
                requirement: $0,
                profile: profile,
                environment: environment,
                fileManager: fileManager
            )
        }
        let blockedCount = results.filter { $0.status == .blocked }.count
        let passedCount = results.count - blockedCount
        let failures = results
            .filter { $0.status == .blocked }
            .map {
                SignoffDeckFailure(
                    code: "signoff_foundry_deck_blocked",
                    deckID: $0.deckID,
                    domain: $0.domain,
                    backendID: $0.backendID,
                    diagnostics: $0.diagnostics
                )
            }
        return SignoffDeckInventoryReport(
            generatedAt: generatedAt ?? utcTimestamp(),
            status: blockedCount == 0 ? .passed : .blocked,
            checkedDeckCount: results.count,
            passedDeckCount: passedCount,
            blockedDeckCount: blockedCount,
            results: results,
            failures: failures
        )
    }

    private static func inspect(
        requirement: SignoffDeckRequirement,
        profile: SignoffPDKProfile,
        environment: [String: String],
        fileManager: FileManager
    ) -> SignoffDeckResult {
        guard profile.requirement(withID: requirement.pdkRequirement) != nil else {
            return blockedResult(
                requirement: requirement,
                pdkRoot: nil,
                requiredFile: nil,
                requiredFileExists: false,
                diagnostic: SignoffDeckDiagnostic(
                    code: "unknown_pdk_requirement",
                    message: "The requested PDK requirement is not declared by the signoff PDK profile."
                )
            )
        }

        guard let pdkRoot = SignoffPDKLocator.root(
            requirementID: requirement.pdkRequirement,
            profile: profile,
            environment: environment,
            fileManager: fileManager
        ) else {
            let candidateRoot = environment["PDK_ROOT"]
            let candidateFile = candidateRoot.flatMap {
                candidateRequiredFile(
                    pdkRoot: $0,
                    profile: profile,
                    requirementID: requirement.pdkRequirement
                )
            }
            return blockedResult(
                requirement: requirement,
                pdkRoot: candidateRoot,
                requiredFile: candidateFile,
                requiredFileExists: false,
                diagnostic: SignoffDeckDiagnostic(
                    code: "missing_pdk_required_file",
                    message: "The required PDK deck file is not available."
                )
            )
        }

        let requiredFile: String
        do {
            requiredFile = try SignoffPDKLocator.requiredFileURL(
                in: pdkRoot,
                profile: profile,
                requirementID: requirement.pdkRequirement
            ).path(percentEncoded: false)
        } catch {
            return blockedResult(
                requirement: requirement,
                pdkRoot: pdkRoot,
                requiredFile: nil,
                requiredFileExists: false,
                diagnostic: SignoffDeckDiagnostic(
                    code: "unknown_pdk_requirement",
                    message: "The resolved PDK profile does not declare the required deck file."
                )
            )
        }
        let exists = fileManager.fileExists(atPath: requiredFile)
        if !exists {
            return blockedResult(
                requirement: requirement,
                pdkRoot: pdkRoot,
                requiredFile: requiredFile,
                requiredFileExists: false,
                diagnostic: SignoffDeckDiagnostic(
                    code: "missing_pdk_required_file",
                    message: "The resolved PDK root does not contain the required deck file."
                )
            )
        }

        return SignoffDeckResult(
            deckID: requirement.deckID,
            domain: requirement.domain,
            backendID: requirement.backendID,
            pdkRequirement: requirement.pdkRequirement,
            status: .passed,
            pdkRoot: pdkRoot,
            requiredFile: requiredFile,
            requiredFileExists: true,
            requiredCoverageTags: requirement.requiredCoverageTags,
            diagnostics: []
        )
    }

    private static func blockedResult(
        requirement: SignoffDeckRequirement,
        pdkRoot: String?,
        requiredFile: String?,
        requiredFileExists: Bool,
        diagnostic: SignoffDeckDiagnostic
    ) -> SignoffDeckResult {
        SignoffDeckResult(
            deckID: requirement.deckID,
            domain: requirement.domain,
            backendID: requirement.backendID,
            pdkRequirement: requirement.pdkRequirement,
            status: .blocked,
            pdkRoot: pdkRoot,
            requiredFile: requiredFile,
            requiredFileExists: requiredFileExists,
            requiredCoverageTags: requirement.requiredCoverageTags,
            diagnostics: [diagnostic]
        )
    }

    private static func candidateRequiredFile(
        pdkRoot: String,
        profile: SignoffPDKProfile,
        requirementID: String
    ) -> String? {
        do {
            return try SignoffPDKLocator.requiredFileURL(
                in: pdkRoot,
                profile: profile,
                requirementID: requirementID
            ).path(percentEncoded: false)
        } catch {
            return nil
        }
    }

    private static func utcTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
