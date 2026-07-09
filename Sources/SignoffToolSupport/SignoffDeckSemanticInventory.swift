import Foundation

public struct SignoffDeckSemanticSource: Codable, Sendable, Hashable {
    public let path: String
    public let role: String
    public let lineCount: Int

    public init(path: String, role: String, lineCount: Int) {
        self.path = path
        self.role = role
        self.lineCount = lineCount
    }
}

public struct SignoffDeckSemanticCoverage: Codable, Sendable, Hashable {
    public let tag: String
    public let status: SignoffDeckStatus
    public let evidenceCount: Int
    public let sourceRoles: [String]
    public let diagnostics: [SignoffDeckDiagnostic]

    public init(
        tag: String,
        status: SignoffDeckStatus,
        evidenceCount: Int,
        sourceRoles: [String],
        diagnostics: [SignoffDeckDiagnostic]
    ) {
        self.tag = tag
        self.status = status
        self.evidenceCount = evidenceCount
        self.sourceRoles = sourceRoles
        self.diagnostics = diagnostics
    }
}

public struct MagicDRCSemanticSummary: Codable, Sendable, Hashable {
    public let ruleFamilyCounts: [String: Int]
    public let totalRuleCount: Int
    public let cutClassCount: Int?
    public let contactStackCount: Int?
    public let wiringContactCount: Int?
    public let exactOverlapCount: Int?
    public let enclosedHoleCount: Int?
    public let hasTechLoad: Bool
    public let hasScaleGrid: Bool
    public let hasSnapLambda: Bool

    public init(
        ruleFamilyCounts: [String: Int],
        totalRuleCount: Int,
        cutClassCount: Int? = nil,
        contactStackCount: Int? = nil,
        wiringContactCount: Int? = nil,
        exactOverlapCount: Int? = nil,
        enclosedHoleCount: Int? = nil,
        hasTechLoad: Bool,
        hasScaleGrid: Bool,
        hasSnapLambda: Bool
    ) {
        self.ruleFamilyCounts = ruleFamilyCounts
        self.totalRuleCount = totalRuleCount
        self.cutClassCount = cutClassCount
        self.contactStackCount = contactStackCount
        self.wiringContactCount = wiringContactCount
        self.exactOverlapCount = exactOverlapCount
        self.enclosedHoleCount = enclosedHoleCount
        self.hasTechLoad = hasTechLoad
        self.hasScaleGrid = hasScaleGrid
        self.hasSnapLambda = hasSnapLambda
    }
}

public struct NetgenLVSSemanticSummary: Codable, Sendable, Hashable {
    public let deviceFamilyCounts: [String: Int]
    public let totalDeviceCount: Int
    public let permuteRuleCount: Int
    public let propertyRuleCount: Int
    public let equateRuleCount: Int
    public let blackboxRuleCount: Int

    public init(
        deviceFamilyCounts: [String: Int],
        totalDeviceCount: Int,
        permuteRuleCount: Int,
        propertyRuleCount: Int,
        equateRuleCount: Int,
        blackboxRuleCount: Int
    ) {
        self.deviceFamilyCounts = deviceFamilyCounts
        self.totalDeviceCount = totalDeviceCount
        self.permuteRuleCount = permuteRuleCount
        self.propertyRuleCount = propertyRuleCount
        self.equateRuleCount = equateRuleCount
        self.blackboxRuleCount = blackboxRuleCount
    }
}

public struct SignoffDeckSemanticFailure: Codable, Sendable, Hashable {
    public let code: String
    public let coverageTag: String
    public let diagnostics: [SignoffDeckDiagnostic]

    public init(code: String, coverageTag: String, diagnostics: [SignoffDeckDiagnostic]) {
        self.code = code
        self.coverageTag = coverageTag
        self.diagnostics = diagnostics
    }
}

public struct SignoffDeckSemanticReport: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let kind: String
    public let generatedAt: String
    public let status: SignoffDeckStatus
    public let pdkRoot: String?
    public let sources: [SignoffDeckSemanticSource]
    public let magicDRC: MagicDRCSemanticSummary?
    public let netgenLVS: NetgenLVSSemanticSummary?
    public let coverageTagResults: [SignoffDeckSemanticCoverage]
    public let failures: [SignoffDeckSemanticFailure]

    public init(
        schemaVersion: Int = 1,
        kind: String = "signoff-foundry-deck-semantics",
        generatedAt: String,
        status: SignoffDeckStatus,
        pdkRoot: String?,
        sources: [SignoffDeckSemanticSource],
        magicDRC: MagicDRCSemanticSummary?,
        netgenLVS: NetgenLVSSemanticSummary?,
        coverageTagResults: [SignoffDeckSemanticCoverage],
        failures: [SignoffDeckSemanticFailure]
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.generatedAt = generatedAt
        self.status = status
        self.pdkRoot = pdkRoot
        self.sources = sources
        self.magicDRC = magicDRC
        self.netgenLVS = netgenLVS
        self.coverageTagResults = coverageTagResults
        self.failures = failures
    }
}

public enum SignoffDeckSemanticInventory {
    public static func inspect(
        profile: SignoffPDKProfile,
        requirements: [SignoffDeckRequirement]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        generatedAt: String? = nil
    ) -> SignoffDeckSemanticReport {
        let activeRequirements = requirements ?? profile.deckRequirements
        let requiredCoverageTags = requiredCoverageTags(for: activeRequirements)
        let readiness = SignoffDeckInventory.inspect(
            profile: profile,
            requirements: activeRequirements,
            environment: environment,
            fileManager: fileManager,
            generatedAt: generatedAt
        )
        guard readiness.status == .passed, let pdkRoot = readiness.results.compactMap(\.pdkRoot).first else {
            let coverage = requiredCoverageTags.map {
                blockedCoverage(tag: $0, code: "foundry_deck_readiness_blocked")
            }
            return report(
                generatedAt: generatedAt,
                pdkRoot: readiness.results.compactMap(\.pdkRoot).first,
                sources: [],
                magicDRC: nil,
                netgenLVS: nil,
                coverage: coverage
            )
        }

        var sources: [SignoffDeckSemanticSource] = []
        var sourceTextByRole: [String: String] = [:]
        var sourceDiagnosticsByRole: [String: [SignoffDeckDiagnostic]] = [:]
        for sourceRequirement in profile.semanticSources
            where shouldReadSource(role: sourceRequirement.role, requiredCoverageTags: requiredCoverageTags) {
            let sourceURL: URL
            do {
                sourceURL = try SignoffPDKLocator.requiredFileURL(
                    in: pdkRoot,
                    profile: profile,
                    requirementID: sourceRequirement.requirementID
                )
            } catch {
                appendSourceDiagnostic(
                    role: sourceRequirement.role,
                    diagnostic: SignoffDeckDiagnostic(
                        code: "semantic_source_requirement_missing",
                        message: "The semantic source requirement '\(sourceRequirement.requirementID)' for role '\(sourceRequirement.role)' is not declared by the signoff PDK profile."
                    ),
                    to: &sourceDiagnosticsByRole
                )
                continue
            }
            let path = sourceURL.path(percentEncoded: false)
            guard fileManager.fileExists(atPath: path) else {
                appendSourceDiagnostic(
                    role: sourceRequirement.role,
                    diagnostic: SignoffDeckDiagnostic(
                        code: "semantic_source_file_missing",
                        message: "The semantic source file for role '\(sourceRequirement.role)' is missing at \(path)."
                    ),
                    to: &sourceDiagnosticsByRole
                )
                continue
            }
            let text: String
            do {
                text = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                appendSourceDiagnostic(
                    role: sourceRequirement.role,
                    diagnostic: SignoffDeckDiagnostic(
                        code: "semantic_source_file_unreadable",
                        message: "The semantic source file for role '\(sourceRequirement.role)' could not be read at \(path): \(error.localizedDescription)"
                    ),
                    to: &sourceDiagnosticsByRole
                )
                continue
            }
            sourceTextByRole[sourceRequirement.role] = text
            sources.append(source(path: path, role: sourceRequirement.role, text: text))
        }

        let magicDRC = sourceTextByRole["magic-tech"].map {
            buildMagicDRCSummary(magicrc: sourceTextByRole["magicrc"] ?? "", magicTech: $0)
        }
        let netgenLVS = sourceTextByRole["netgen-setup"].map(buildNetgenLVSSummary)
        let coverage = evaluateCoverage(
            profile: profile,
            sourceTextByRole: sourceTextByRole,
            sourceDiagnosticsByRole: sourceDiagnosticsByRole,
            magicDRC: magicDRC,
            netgenLVS: netgenLVS
        ).filter { requiredCoverageTags.contains($0.tag) }
        return report(
            generatedAt: generatedAt,
            pdkRoot: pdkRoot,
            sources: sources,
            magicDRC: magicDRC,
            netgenLVS: netgenLVS,
            coverage: coverage
        )
    }

    private static func report(
        generatedAt: String?,
        pdkRoot: String?,
        sources: [SignoffDeckSemanticSource],
        magicDRC: MagicDRCSemanticSummary?,
        netgenLVS: NetgenLVSSemanticSummary?,
        coverage: [SignoffDeckSemanticCoverage]
    ) -> SignoffDeckSemanticReport {
        let failures = coverage
            .filter { $0.status == .blocked }
            .map {
                SignoffDeckSemanticFailure(
                    code: "foundry_deck_semantic_coverage_blocked",
                    coverageTag: $0.tag,
                    diagnostics: $0.diagnostics
                )
            }
        return SignoffDeckSemanticReport(
            generatedAt: generatedAt ?? utcTimestamp(),
            status: failures.isEmpty ? .passed : .blocked,
            pdkRoot: pdkRoot,
            sources: sources,
            magicDRC: magicDRC,
            netgenLVS: netgenLVS,
            coverageTagResults: coverage,
            failures: failures
        )
    }

    private static func buildMagicDRCSummary(
        magicrc: String,
        magicTech: String
    ) -> MagicDRCSemanticSummary {
        let lines = magicTech.split(whereSeparator: \.isNewline).map(String.init)
        var inDRC = false
        var inContact = false
        var inWiring = false
        var counts: [String: Int] = [:]
        var cutClassCount = 0
        var contactStackCount = 0
        var wiringContactCount = 0
        var exactOverlapCount = 0
        for rawLine in lines {
            let line = normalizedLine(rawLine)
            let tokens = commandTokens(line)
            guard let command = tokens.first else {
                continue
            }
            if line.hasPrefix("cut ") {
                cutClassCount += 1
            }
            if command == "contact", tokens.count == 1 {
                inContact = true
                continue
            }
            if inContact && command == "end" {
                inContact = false
                continue
            }
            if inContact && command != "stackable", tokens.count >= 3 {
                contactStackCount += 1
            }
            if line == "wiring" {
                inWiring = true
                continue
            }
            if inWiring && line == "end" {
                inWiring = false
                continue
            }
            if inWiring && line.hasPrefix("contact ") {
                wiringContactCount += 1
            }
            if inDRC && line.hasPrefix("exact_overlap ") {
                exactOverlapCount += 1
            }
            if line == "drc" {
                inDRC = true
                continue
            }
            if inDRC && line == "end" {
                inDRC = false
                continue
            }
            guard inDRC, let family = commandFamily(line) else {
                continue
            }
            counts[family, default: 0] += 1
        }
        let total = counts.values.reduce(0, +)
        let magicrcLines = magicrc.split(whereSeparator: \.isNewline).map { normalizedLine(String($0)) }
        let techLines = magicTech.split(whereSeparator: \.isNewline).map { normalizedLine(String($0)) }
        return MagicDRCSemanticSummary(
            ruleFamilyCounts: counts,
            totalRuleCount: total,
            cutClassCount: cutClassCount,
            contactStackCount: contactStackCount,
            wiringContactCount: wiringContactCount,
            exactOverlapCount: exactOverlapCount,
            enclosedHoleCount: countEnclosedHoleRules(in: magicTech),
            hasTechLoad: magicrcLines.contains { $0.hasPrefix("tech load ") },
            hasScaleGrid: magicrcLines.contains { $0.hasPrefix("scalegrid ") } || techLines.contains { $0.hasPrefix("scale ") },
            hasSnapLambda: magicrcLines.contains { $0 == "snap lambda" }
        )
    }

    private static func buildNetgenLVSSummary(_ text: String) -> NetgenLVSSemanticSummary {
        let lines = text.split(whereSeparator: \.isNewline).map { normalizedLine(String($0)) }
        var families: [String: Int] = [:]
        var totalDevices = 0
        var permute = 0
        var property = 0
        var equate = 0
        var blackbox = 0
        for line in lines {
            if line.hasPrefix("lappend devices ") {
                let devices = line.dropFirst("lappend devices ".count).split(separator: " ").map(String.init)
                for device in devices {
                    totalDevices += 1
                    families[deviceFamily(device), default: 0] += 1
                }
            } else if line.hasPrefix("permute ") {
                permute += 1
            } else if line.hasPrefix("property ") {
                property += 1
            } else if line.hasPrefix("equate ") {
                equate += 1
            } else if line.contains("model blackbox") {
                blackbox += 1
            }
        }
        return NetgenLVSSemanticSummary(
            deviceFamilyCounts: families,
            totalDeviceCount: totalDevices,
            permuteRuleCount: permute,
            propertyRuleCount: property,
            equateRuleCount: equate,
            blackboxRuleCount: blackbox
        )
    }

    private static func evaluateCoverage(
        profile: SignoffPDKProfile,
        sourceTextByRole: [String: String],
        sourceDiagnosticsByRole: [String: [SignoffDeckDiagnostic]],
        magicDRC: MagicDRCSemanticSummary?,
        netgenLVS: NetgenLVSSemanticSummary?
    ) -> [SignoffDeckSemanticCoverage] {
        profile.semanticChecks.map { check in
            evaluate(
                check: check,
                sourceTextByRole: sourceTextByRole,
                sourceDiagnosticsByRole: sourceDiagnosticsByRole,
                magicDRC: magicDRC,
                netgenLVS: netgenLVS
            )
        }
    }

    private static func evaluate(
        check: SignoffDeckSemanticCheck,
        sourceTextByRole: [String: String],
        sourceDiagnosticsByRole: [String: [SignoffDeckDiagnostic]],
        magicDRC: MagicDRCSemanticSummary?,
        netgenLVS: NetgenLVSSemanticSummary?
    ) -> SignoffDeckSemanticCoverage {
        let sourceAvailable = check.sourceRoles.contains { sourceTextByRole[$0] != nil }
        let sourceDiagnostics = check.sourceRoles.flatMap { sourceDiagnosticsByRole[$0] ?? [] }
        let result: (evidenceCount: Int, passed: Bool)
        switch check.evaluator {
        case "magic-tech-available":
            result = (sourceAvailable ? 1 : 0, sourceAvailable)
        case "magic-required-rule-families-present":
            let requiredFamilies = check.requiredValues ?? []
            result = (
                magicDRC?.totalRuleCount ?? 0,
                !requiredFamilies.isEmpty
                    && requiredFamilies.allSatisfy { (magicDRC?.ruleFamilyCounts[$0] ?? 0) > 0 }
            )
        case "magic-cut-classes-present":
            let count = magicDRC?.cutClassCount ?? 0
            result = (count, count > 0)
        case "magic-contact-geometry-present":
            let count = (magicDRC?.contactStackCount ?? 0) + (magicDRC?.wiringContactCount ?? 0)
            result = (count, count > 0)
        case "magic-exact-overlap-present":
            let count = magicDRC?.exactOverlapCount ?? 0
            result = (count, count > 0)
        case "magic-enclosed-hole-present":
            let count = magicDRC?.enclosedHoleCount ?? 0
            result = (count, count > 0)
        case "magic-unit-scaling-present":
            let count = [
                magicDRC?.hasTechLoad == true,
                magicDRC?.hasScaleGrid == true,
                magicDRC?.hasSnapLambda == true
            ].filter { $0 }.count
            result = (
                count,
                sourceAvailable
                    && magicDRC?.hasTechLoad == true
                    && magicDRC?.hasScaleGrid == true
                    && magicDRC?.hasSnapLambda == true
            )
        case "netgen-setup-available":
            result = (sourceAvailable ? 1 : 0, sourceAvailable)
        case "netgen-required-device-families-present":
            let requiredFamilies = check.requiredValues ?? []
            result = (
                netgenLVS?.totalDeviceCount ?? 0,
                !requiredFamilies.isEmpty
                    && requiredFamilies.allSatisfy { (netgenLVS?.deviceFamilyCounts[$0] ?? 0) > 0 }
            )
        case "netgen-pin-policy-present":
            let count = (netgenLVS?.permuteRuleCount ?? 0)
                + (netgenLVS?.propertyRuleCount ?? 0)
                + (netgenLVS?.equateRuleCount ?? 0)
            result = (
                count,
                (netgenLVS?.permuteRuleCount ?? 0) > 0
                    && (netgenLVS?.propertyRuleCount ?? 0) > 0
                    && (netgenLVS?.equateRuleCount ?? 0) > 0
            )
        default:
            result = (0, false)
        }
        let blockedCode = check.evaluator.isEmpty ? "unknown_semantic_check" : check.blockedCode
        return coverage(
            tag: check.tag,
            evidenceCount: result.evidenceCount,
            sourceRoles: check.sourceRoles,
            passed: result.passed && sourceDiagnostics.isEmpty,
            blockedCode: blockedCode,
            sourceDiagnostics: sourceDiagnostics
        )
    }

    private static func coverage(
        tag: String,
        evidenceCount: Int,
        sourceRoles: [String],
        passed: Bool,
        blockedCode: String,
        sourceDiagnostics: [SignoffDeckDiagnostic] = []
    ) -> SignoffDeckSemanticCoverage {
        let diagnostics = passed ? [] : sourceDiagnostics + [
            SignoffDeckDiagnostic(
                code: blockedCode,
                message: "The signoff deck semantic inventory did not find required evidence for this coverage tag."
            )
        ]
        return SignoffDeckSemanticCoverage(
            tag: tag,
            status: passed ? .passed : .blocked,
            evidenceCount: evidenceCount,
            sourceRoles: sourceRoles,
            diagnostics: diagnostics
        )
    }

    private static func blockedCoverage(tag: String, code: String) -> SignoffDeckSemanticCoverage {
        SignoffDeckSemanticCoverage(
            tag: tag,
            status: .blocked,
            evidenceCount: 0,
            sourceRoles: [],
            diagnostics: [
                SignoffDeckDiagnostic(
                    code: code,
                    message: "The signoff deck semantic inventory could not run because deck readiness is blocked."
                )
            ]
        )
    }

    private static func shouldReadSource(role: String, requiredCoverageTags: [String]) -> Bool {
        if role.hasPrefix("magic") {
            return requiredCoverageTags.contains { $0.hasPrefix("drc.") }
        }
        if role.hasPrefix("netgen") {
            return requiredCoverageTags.contains { $0.hasPrefix("lvs.") }
        }
        return true
    }

    private static func source(path: String, role: String, text: String) -> SignoffDeckSemanticSource {
        SignoffDeckSemanticSource(
            path: path,
            role: role,
            lineCount: text.split(whereSeparator: \.isNewline).count
        )
    }

    private static func appendSourceDiagnostic(
        role: String,
        diagnostic: SignoffDeckDiagnostic,
        to diagnosticsByRole: inout [String: [SignoffDeckDiagnostic]]
    ) {
        diagnosticsByRole[role, default: []].append(diagnostic)
    }

    private static func normalizedLine(_ rawLine: String) -> String {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let commentIndex = trimmed.firstIndex(of: "#") else {
            return trimmed
        }
        return String(trimmed[..<commentIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func commandFamily(_ line: String) -> String? {
        for family in observedMagicRuleFamilies {
            if line == family || line.hasPrefix("\(family) ") {
                return family
            }
        }
        return nil
    }

    private static func countEnclosedHoleRules(in magicTech: String) -> Int {
        let lines = magicTech
            .split(whereSeparator: \.isNewline)
            .map { normalizedLine(String($0)) }
            .filter { !$0.isEmpty }
        var currentTempLayer: String?
        var smallHoleLayersWithClose: Set<String> = []
        var holeLayerSources: [String: String] = [:]
        for line in lines {
            let tokens = commandTokens(line)
            guard let command = tokens.first else {
                continue
            }
            if command == "templayer", tokens.count >= 2 {
                currentTempLayer = tokens[1]
                if tokens.count >= 3, tokens[1].hasSuffix("_hole_empty") {
                    holeLayerSources[tokens[1]] = tokens[2]
                }
                continue
            }
            if command == "close",
               let currentTempLayer,
               currentTempLayer.hasSuffix("_small_hole"),
               tokens.count >= 2,
               isPositiveNumber(tokens[1]) {
                smallHoleLayersWithClose.insert(currentTempLayer)
            }
        }

        var importedHoleLayers: Set<String> = []
        for line in lines {
            let tokens = commandTokens(line)
            guard tokens.count >= 4, tokens[0] == "cifmaxwidth" else {
                continue
            }
            let holeLayer = tokens[1]
            guard let sourceLayer = holeLayerSources[holeLayer],
                  smallHoleLayersWithClose.contains(sourceLayer),
                  isZeroNumber(tokens[2]) else {
                continue
            }
            importedHoleLayers.insert(holeLayer)
        }
        return importedHoleLayers.count
    }

    private static func commandTokens(_ line: String) -> [String] {
        line.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func isPositiveNumber(_ text: String) -> Bool {
        guard let value = Double(text) else {
            return false
        }
        return value > 0
    }

    private static func isZeroNumber(_ text: String) -> Bool {
        guard let value = Double(text) else {
            return false
        }
        return value == 0
    }

    private static func deviceFamily(_ device: String) -> String {
        if device.contains("nfet") || device.contains("pfet") {
            return "mos"
        }
        if device.contains("res_") || device.hasPrefix("mrd") {
            return "resistor"
        }
        if device.contains("diode") {
            return "diode"
        }
        if device.contains("cap_") || device.contains("__cap") {
            return "capacitor"
        }
        if device.contains("npn") || device.contains("pnp") {
            return "bjt"
        }
        if device.contains("ind_") {
            return "inductor"
        }
        return "other"
    }

    private static func requiredCoverageTags(
        for requirements: [SignoffDeckRequirement]
    ) -> [String] {
        var seen: Set<String> = []
        var tags: [String] = []
        for tag in requirements.flatMap(\.requiredCoverageTags) where !seen.contains(tag) {
            seen.insert(tag)
            tags.append(tag)
        }
        return tags
    }

    private static let observedMagicRuleFamilies = [
        "width",
        "spacing",
        "surround",
        "overhang",
        "area",
        "widespacing",
        "notch",
        "rect_only",
        "variants",
    ]

    private static func utcTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
