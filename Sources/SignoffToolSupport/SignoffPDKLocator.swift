import Foundation

public enum SignoffPDKProfileError: Error, Sendable, Hashable {
    case missingBundledProfile(String)
    case missingRequirement(String)
    case unsupportedSchemaVersion(Int)
    case emptyField(String)
    case duplicateRequirementID(String)
    case unsafeRelativePath(requirementID: String, relativePath: String)
    case missingReferencedRequirement(field: String, requirementID: String)
}

public struct SignoffPDKRequiredFile: Codable, Sendable, Hashable {
    public let requirementID: String
    public let relativePath: String

    public init(requirementID: String, relativePath: String) {
        self.requirementID = requirementID
        self.relativePath = relativePath
    }
}

public struct SignoffPDKStandardCellLibrary: Codable, Sendable, Hashable {
    public let libraryID: String
    public let spiceDeckRequirementID: String

    public init(libraryID: String, spiceDeckRequirementID: String) {
        self.libraryID = libraryID
        self.spiceDeckRequirementID = spiceDeckRequirementID
    }
}

public struct SignoffDeckSemanticSourceRequirement: Codable, Sendable, Hashable {
    public let requirementID: String
    public let role: String

    public init(requirementID: String, role: String) {
        self.requirementID = requirementID
        self.role = role
    }
}

public struct SignoffDeckSemanticCheck: Codable, Sendable, Hashable {
    public let tag: String
    public let evaluator: String
    public let sourceRoles: [String]
    public let blockedCode: String
    public let requiredValues: [String]?

    public init(
        tag: String,
        evaluator: String,
        sourceRoles: [String],
        blockedCode: String,
        requiredValues: [String] = []
    ) {
        self.tag = tag
        self.evaluator = evaluator
        self.sourceRoles = sourceRoles
        self.blockedCode = blockedCode
        self.requiredValues = requiredValues
    }
}

public struct SignoffPDKProfile: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let profileID: String
    public let pdkID: String
    public let rootDirectoryName: String?
    public let candidateRootPaths: [String]
    public let requirements: [SignoffPDKRequiredFile]
    public let standardCellLibraries: [SignoffPDKStandardCellLibrary]
    public let deckRequirements: [SignoffDeckRequirement]
    public let semanticSources: [SignoffDeckSemanticSourceRequirement]
    public let semanticChecks: [SignoffDeckSemanticCheck]

    public init(
        schemaVersion: Int = 1,
        profileID: String,
        pdkID: String,
        rootDirectoryName: String?,
        candidateRootPaths: [String],
        requirements: [SignoffPDKRequiredFile],
        standardCellLibraries: [SignoffPDKStandardCellLibrary] = [],
        deckRequirements: [SignoffDeckRequirement],
        semanticSources: [SignoffDeckSemanticSourceRequirement],
        semanticChecks: [SignoffDeckSemanticCheck]
    ) throws {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.pdkID = pdkID
        self.rootDirectoryName = rootDirectoryName
        self.candidateRootPaths = candidateRootPaths
        self.requirements = requirements
        self.standardCellLibraries = standardCellLibraries
        self.deckRequirements = deckRequirements
        self.semanticSources = semanticSources
        self.semanticChecks = semanticChecks
        try validate()
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profileID
        case pdkID
        case rootDirectoryName
        case candidateRootPaths
        case requirements
        case standardCellLibraries
        case deckRequirements
        case semanticSources
        case semanticChecks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        profileID = try container.decode(String.self, forKey: .profileID)
        pdkID = try container.decode(String.self, forKey: .pdkID)
        rootDirectoryName = try container.decodeIfPresent(String.self, forKey: .rootDirectoryName)
        candidateRootPaths = try container.decode([String].self, forKey: .candidateRootPaths)
        requirements = try container.decode([SignoffPDKRequiredFile].self, forKey: .requirements)
        standardCellLibraries = try container.decodeIfPresent(
            [SignoffPDKStandardCellLibrary].self,
            forKey: .standardCellLibraries
        ) ?? []
        deckRequirements = try container.decode([SignoffDeckRequirement].self, forKey: .deckRequirements)
        semanticSources = try container.decode([SignoffDeckSemanticSourceRequirement].self, forKey: .semanticSources)
        semanticChecks = try container.decode([SignoffDeckSemanticCheck].self, forKey: .semanticChecks)
        try validate()
    }

    public static func load(from url: URL) throws -> SignoffPDKProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SignoffPDKProfile.self, from: data)
    }

    public static func bundledProfile(resourceName: String) throws -> SignoffPDKProfile {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw SignoffPDKProfileError.missingBundledProfile(resourceName)
        }
        return try load(from: url)
    }

    public func requirement(withID requirementID: String) -> SignoffPDKRequiredFile? {
        requirements.first { $0.requirementID == requirementID }
    }

    public func deckRequirements(domain: String, backendID: String? = nil) -> [SignoffDeckRequirement] {
        deckRequirements.filter { requirement in
            requirement.domain == domain && (backendID == nil || requirement.backendID == backendID)
        }
    }

    private func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SignoffPDKProfileError.unsupportedSchemaVersion(schemaVersion)
        }
        try Self.requireNonEmpty(profileID, field: "profileID")
        try Self.requireNonEmpty(pdkID, field: "pdkID")
        if let rootDirectoryName {
            try Self.requireNonEmpty(rootDirectoryName, field: "rootDirectoryName")
        }
        try validateRequirements()
        let requirementIDs = Set(requirements.map(\.requirementID))
        try validateStandardCellLibraries(requirementIDs: requirementIDs)
        try validateDeckRequirements(requirementIDs: requirementIDs)
        try validateSemanticSources(requirementIDs: requirementIDs)
        try validateSemanticChecks()
    }

    private func validateRequirements() throws {
        var seen: Set<String> = []
        for (index, requirement) in requirements.enumerated() {
            try Self.requireNonEmpty(requirement.requirementID, field: "requirements[\(index)].requirementID")
            try Self.requireNonEmpty(requirement.relativePath, field: "requirements[\(index)].relativePath")
            guard seen.insert(requirement.requirementID).inserted else {
                throw SignoffPDKProfileError.duplicateRequirementID(requirement.requirementID)
            }
            guard Self.isSafeRelativePath(requirement.relativePath) else {
                throw SignoffPDKProfileError.unsafeRelativePath(
                    requirementID: requirement.requirementID,
                    relativePath: requirement.relativePath
                )
            }
        }
    }

    private func validateStandardCellLibraries(requirementIDs: Set<String>) throws {
        for (index, library) in standardCellLibraries.enumerated() {
            try Self.requireNonEmpty(library.libraryID, field: "standardCellLibraries[\(index)].libraryID")
            try Self.requireNonEmpty(
                library.spiceDeckRequirementID,
                field: "standardCellLibraries[\(index)].spiceDeckRequirementID"
            )
            guard requirementIDs.contains(library.spiceDeckRequirementID) else {
                throw SignoffPDKProfileError.missingReferencedRequirement(
                    field: "standardCellLibraries[\(index)].spiceDeckRequirementID",
                    requirementID: library.spiceDeckRequirementID
                )
            }
        }
    }

    private func validateDeckRequirements(requirementIDs: Set<String>) throws {
        for (index, deck) in deckRequirements.enumerated() {
            try Self.requireNonEmpty(deck.deckID, field: "deckRequirements[\(index)].deckID")
            try Self.requireNonEmpty(deck.domain, field: "deckRequirements[\(index)].domain")
            try Self.requireNonEmpty(deck.backendID, field: "deckRequirements[\(index)].backendID")
            try Self.requireNonEmpty(deck.pdkRequirement, field: "deckRequirements[\(index)].pdkRequirement")
            guard requirementIDs.contains(deck.pdkRequirement) else {
                throw SignoffPDKProfileError.missingReferencedRequirement(
                    field: "deckRequirements[\(index)].pdkRequirement",
                    requirementID: deck.pdkRequirement
                )
            }
        }
    }

    private func validateSemanticSources(requirementIDs: Set<String>) throws {
        for (index, source) in semanticSources.enumerated() {
            try Self.requireNonEmpty(source.requirementID, field: "semanticSources[\(index)].requirementID")
            try Self.requireNonEmpty(source.role, field: "semanticSources[\(index)].role")
            guard requirementIDs.contains(source.requirementID) else {
                throw SignoffPDKProfileError.missingReferencedRequirement(
                    field: "semanticSources[\(index)].requirementID",
                    requirementID: source.requirementID
                )
            }
        }
    }

    private func validateSemanticChecks() throws {
        for (index, check) in semanticChecks.enumerated() {
            try Self.requireNonEmpty(check.tag, field: "semanticChecks[\(index)].tag")
            try Self.requireNonEmpty(check.evaluator, field: "semanticChecks[\(index)].evaluator")
            try Self.requireNonEmpty(check.blockedCode, field: "semanticChecks[\(index)].blockedCode")
            for (roleIndex, role) in check.sourceRoles.enumerated() {
                try Self.requireNonEmpty(role, field: "semanticChecks[\(index)].sourceRoles[\(roleIndex)]")
            }
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SignoffPDKProfileError.emptyField(field)
        }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        if path.hasPrefix("/") || path.hasPrefix("~") || path.contains("://") {
            return false
        }
        let components = NSString(string: path).pathComponents
        return components.allSatisfy { component in
            component != "." && component != ".." && component != "/"
        }
    }
}

public enum SignoffPDKLocator {
    public static func root(
        requirementID: String,
        profile: SignoffPDKProfile,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let pdkRoot = environment["PDK_ROOT"] {
            if hasRequiredFile(
                in: pdkRoot,
                requirementID: requirementID,
                profile: profile,
                fileManager: fileManager
            ) {
                return toolRoot(for: pdkRoot, profile: profile)
            }
            return nil
        }

        for candidate in profile.candidateRootPaths.map(expandTilde) {
            if hasRequiredFile(
                in: candidate,
                requirementID: requirementID,
                profile: profile,
                fileManager: fileManager
            ) {
                return toolRoot(for: candidate, profile: profile)
            }
            if let versioned = singleVersionedRoot(
                at: candidate,
                requirementID: requirementID,
                profile: profile,
                fileManager: fileManager
            ) {
                return toolRoot(for: versioned, profile: profile)
            }
        }
        return nil
    }

    public static func requiredFileURL(
        in pdkRoot: String,
        profile: SignoffPDKProfile,
        requirementID: String,
        substitutions: [String: String] = [:]
    ) throws -> URL {
        guard let requirement = profile.requirement(withID: requirementID) else {
            throw SignoffPDKProfileError.missingRequirement(requirementID)
        }
        let relativePath = substitutedPath(requirement.relativePath, substitutions: substitutions)
        guard SignoffPDKProfile.isSafeRelativePath(relativePath) else {
            throw SignoffPDKProfileError.unsafeRelativePath(
                requirementID: requirementID,
                relativePath: relativePath
            )
        }
        let root = URL(filePath: pdkRoot)
        if let rootDirectoryName = profile.rootDirectoryName,
           root.lastPathComponent != rootDirectoryName {
            return root
                .appending(path: rootDirectoryName)
                .appending(path: relativePath)
        }
        return root.appending(path: relativePath)
    }

    private static func hasRequiredFile(
        in pdkRoot: String,
        requirementID: String,
        profile: SignoffPDKProfile,
        fileManager: FileManager
    ) -> Bool {
        do {
            let url = try requiredFileURL(in: pdkRoot, profile: profile, requirementID: requirementID)
            return fileManager.fileExists(atPath: url.path(percentEncoded: false))
        } catch {
            return false
        }
    }

    private static func toolRoot(for pdkRoot: String, profile: SignoffPDKProfile) -> String {
        let url = URL(filePath: pdkRoot)
        guard let rootDirectoryName = profile.rootDirectoryName,
              url.lastPathComponent == rootDirectoryName else {
            return pdkRoot
        }
        return url.deletingLastPathComponent().path(percentEncoded: false)
    }

    private static func singleVersionedRoot(
        at path: String,
        requirementID: String,
        profile: SignoffPDKProfile,
        fileManager: FileManager
    ) -> String? {
        let children: [String]
        do {
            children = try fileManager.contentsOfDirectory(atPath: path)
        } catch {
            return nil
        }
        let roots = children
            .map { URL(filePath: path).appending(path: $0).path(percentEncoded: false) }
            .filter {
                hasRequiredFile(
                    in: $0,
                    requirementID: requirementID,
                    profile: profile,
                    fileManager: fileManager
                )
            }
        return roots.count == 1 ? roots[0] : nil
    }

    private static func expandTilde(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private static func substitutedPath(
        _ path: String,
        substitutions: [String: String]
    ) -> String {
        substitutions.reduce(path) { result, item in
            result.replacingOccurrences(of: "{\(item.key)}", with: item.value)
        }
    }
}
