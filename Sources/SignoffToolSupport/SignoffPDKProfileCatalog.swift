import Foundation

public enum SignoffPDKProfileCatalogError: Error, Sendable, Hashable, LocalizedError {
    case missingBundledResource(String)
    case unsupportedSchemaVersion(Int)
    case invalidKind(String)
    case emptyField(String)
    case emptyCatalog
    case duplicateProfileID(String)
    case missingProfileReference(String)
    case conflictingProfileReference(String)
    case profileNotFound(String)
    case profileIDMismatch(expected: String, actual: String)
    case missingDefaultProfile

    public var errorDescription: String? {
        switch self {
        case .missingBundledResource(let resourceName):
            return "Missing bundled signoff PDK profile catalog resource '\(resourceName)'."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported signoff PDK profile catalog schema version: \(version)."
        case .invalidKind(let kind):
            return "Unsupported signoff PDK profile catalog kind '\(kind)'."
        case .emptyField(let field):
            return "Signoff PDK profile catalog field '\(field)' must not be empty."
        case .emptyCatalog:
            return "Signoff PDK profile catalog must contain at least one profile."
        case .duplicateProfileID(let profileID):
            return "Signoff PDK profile catalog declares duplicate profile ID '\(profileID)'."
        case .missingProfileReference(let profileID):
            return "Signoff PDK profile catalog entry '\(profileID)' must declare a profile resource or profile path."
        case .conflictingProfileReference(let profileID):
            return "Signoff PDK profile catalog entry '\(profileID)' must not declare both a profile resource and profile path."
        case .profileNotFound(let profileID):
            return "Signoff PDK profile catalog does not contain profile ID '\(profileID)'."
        case .profileIDMismatch(let expected, let actual):
            return "Signoff PDK profile catalog entry '\(expected)' loaded profile ID '\(actual)'."
        case .missingDefaultProfile:
            return "Signoff PDK profile catalog has no default profile."
        }
    }
}

public struct SignoffPDKProfileCatalog: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public let profileID: String
        public let displayName: String?
        public let pdkID: String?
        public let profileResourceName: String?
        public let profilePath: String?
        public let defaultProfile: Bool

        public init(
            profileID: String,
            displayName: String? = nil,
            pdkID: String? = nil,
            profileResourceName: String? = nil,
            profilePath: String? = nil,
            defaultProfile: Bool = false
        ) {
            self.profileID = profileID
            self.displayName = displayName
            self.pdkID = pdkID
            self.profileResourceName = profileResourceName
            self.profilePath = profilePath
            self.defaultProfile = defaultProfile
        }

        private enum CodingKeys: String, CodingKey {
            case profileID
            case displayName
            case pdkID
            case profileResourceName
            case profilePath
            case defaultProfile
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profileID = try container.decode(String.self, forKey: .profileID)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            pdkID = try container.decodeIfPresent(String.self, forKey: .pdkID)
            profileResourceName = try container.decodeIfPresent(String.self, forKey: .profileResourceName)
            profilePath = try container.decodeIfPresent(String.self, forKey: .profilePath)
            defaultProfile = try container.decodeIfPresent(Bool.self, forKey: .defaultProfile) ?? false
        }
    }

    public static let currentSchemaVersion = 1
    public static let expectedKind = "signoff-pdk-profile-catalog"
    public static let defaultBundledResourceName = "signoff-pdk-profile-catalog"

    public let schemaVersion: Int
    public let kind: String
    public let catalogID: String
    public let profiles: [Entry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        kind: String = Self.expectedKind,
        catalogID: String,
        profiles: [Entry]
    ) throws {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.catalogID = catalogID
        self.profiles = profiles
        try validate()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        kind = try container.decode(String.self, forKey: .kind)
        catalogID = try container.decode(String.self, forKey: .catalogID)
        profiles = try container.decode([Entry].self, forKey: .profiles)
        try validate()
    }

    public static func load(from url: URL) throws -> SignoffPDKProfileCatalog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SignoffPDKProfileCatalog.self, from: data)
    }

    public static func bundled(
        resourceName: String = Self.defaultBundledResourceName
    ) throws -> SignoffPDKProfileCatalog {
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw SignoffPDKProfileCatalogError.missingBundledResource(resourceName)
        }
        return try load(from: url)
    }

    public static func loadDefaultProfile(
        catalogResourceName: String = Self.defaultBundledResourceName
    ) throws -> SignoffPDKProfile {
        try bundled(resourceName: catalogResourceName).loadProfile()
    }

    public func entry(profileID: String? = nil) throws -> Entry {
        if let profileID {
            guard let entry = profiles.first(where: { $0.profileID == profileID }) else {
                throw SignoffPDKProfileCatalogError.profileNotFound(profileID)
            }
            return entry
        }
        guard let entry = profiles.first(where: \.defaultProfile) ?? profiles.first else {
            throw SignoffPDKProfileCatalogError.missingDefaultProfile
        }
        return entry
    }

    public func loadProfile(profileID: String? = nil) throws -> SignoffPDKProfile {
        let entry = try entry(profileID: profileID)
        let profile: SignoffPDKProfile
        if let resourceName = entry.profileResourceName {
            profile = try SignoffPDKProfile.bundledProfile(resourceName: resourceName)
        } else if let profilePath = entry.profilePath {
            profile = try SignoffPDKProfile.load(from: URL(filePath: profilePath))
        } else {
            throw SignoffPDKProfileCatalogError.missingProfileReference(entry.profileID)
        }
        guard profile.profileID == entry.profileID else {
            throw SignoffPDKProfileCatalogError.profileIDMismatch(
                expected: entry.profileID,
                actual: profile.profileID
            )
        }
        return profile
    }

    private func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SignoffPDKProfileCatalogError.unsupportedSchemaVersion(schemaVersion)
        }
        guard kind == Self.expectedKind else {
            throw SignoffPDKProfileCatalogError.invalidKind(kind)
        }
        try Self.requireNonEmpty(catalogID, field: "catalogID")
        guard !profiles.isEmpty else {
            throw SignoffPDKProfileCatalogError.emptyCatalog
        }

        var seenProfileIDs: Set<String> = []
        var hasDefault = false
        for (index, entry) in profiles.enumerated() {
            try Self.requireNonEmpty(entry.profileID, field: "profiles[\(index)].profileID")
            guard seenProfileIDs.insert(entry.profileID).inserted else {
                throw SignoffPDKProfileCatalogError.duplicateProfileID(entry.profileID)
            }
            if let displayName = entry.displayName {
                try Self.requireNonEmpty(displayName, field: "profiles[\(index)].displayName")
            }
            if let pdkID = entry.pdkID {
                try Self.requireNonEmpty(pdkID, field: "profiles[\(index)].pdkID")
            }
            let hasResource = entry.profileResourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasPath = entry.profilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasResource || hasPath else {
                throw SignoffPDKProfileCatalogError.missingProfileReference(entry.profileID)
            }
            guard !(hasResource && hasPath) else {
                throw SignoffPDKProfileCatalogError.conflictingProfileReference(entry.profileID)
            }
            if entry.defaultProfile {
                hasDefault = true
            }
        }
        guard hasDefault else {
            throw SignoffPDKProfileCatalogError.missingDefaultProfile
        }
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SignoffPDKProfileCatalogError.emptyField(field)
        }
    }
}

public extension SignoffPDKProfile {
    static func bundledDefaultProfile(
        catalogResourceName: String = SignoffPDKProfileCatalog.defaultBundledResourceName
    ) throws -> SignoffPDKProfile {
        try SignoffPDKProfileCatalog.loadDefaultProfile(catalogResourceName: catalogResourceName)
    }
}
