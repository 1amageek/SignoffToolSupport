import Foundation

public enum Sky130PDKRequirement: Sendable, Hashable {
    case magic
    case netgen
}

public enum Sky130PDKLocator {
    public static func root(
        requirement: Sky130PDKRequirement,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let pdkRoot = environment["PDK_ROOT"],
           hasRequiredFile(in: pdkRoot, requirement: requirement, fileManager: fileManager) {
            return pdkRoot
        }

        let candidates = [
            NSString(string: "~/.volare/sky130A").expandingTildeInPath,
            NSString(string: "~/.volare/sky130/versions").expandingTildeInPath,
        ]

        for candidate in candidates {
            if hasRequiredFile(in: candidate, requirement: requirement, fileManager: fileManager) {
                return candidate
            }
            if let versioned = singleVersionedRoot(
                at: candidate,
                requirement: requirement,
                fileManager: fileManager
            ) {
                return versioned
            }
        }
        return nil
    }

    public static func requiredFileURL(
        in pdkRoot: String,
        requirement: Sky130PDKRequirement
    ) -> URL {
        switch requirement {
        case .magic:
            return URL(filePath: pdkRoot).appending(path: "sky130A/libs.tech/magic/sky130A.magicrc")
        case .netgen:
            return URL(filePath: pdkRoot).appending(path: "sky130A/libs.tech/netgen/sky130A_setup.tcl")
        }
    }

    private static func hasRequiredFile(
        in pdkRoot: String,
        requirement: Sky130PDKRequirement,
        fileManager: FileManager
    ) -> Bool {
        fileManager.fileExists(
            atPath: requiredFileURL(in: pdkRoot, requirement: requirement).path(percentEncoded: false)
        )
    }

    private static func singleVersionedRoot(
        at path: String,
        requirement: Sky130PDKRequirement,
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
            .filter { hasRequiredFile(in: $0, requirement: requirement, fileManager: fileManager) }
        return roots.count == 1 ? roots[0] : nil
    }
}
