import CircuiteFoundation

/// Artifact-oriented input boundary for an external signoff tool invocation.
///
/// Process lifetime and cancellation are still owned by `TimedProcessRunner`.
/// This request only describes the immutable evidence inputs that must be
/// available to a domain engine before it launches a tool.
public struct SignoffToolRequest: Sendable, Hashable, Codable {
  public let tool: ProducerIdentity
  public let inputs: [ArtifactReference]
  public let configurationDigest: ContentDigest?
  public let designRevision: ContentDigest?

  public init(
    tool: ProducerIdentity,
    inputs: [ArtifactReference] = [],
    configurationDigest: ContentDigest? = nil,
    designRevision: ContentDigest? = nil
  ) {
    self.tool = tool
    self.inputs = inputs
    self.configurationDigest = configurationDigest
    self.designRevision = designRevision
  }
}

/// Structured result boundary shared by signoff engines and callers.
public struct SignoffToolResult: Sendable, Hashable, Codable, ArtifactProducing,
  DiagnosticReporting, EvidenceProviding
{
  public let artifacts: [ArtifactReference]
  public let diagnostics: [DesignDiagnostic]
  public let evidence: EvidenceManifest

  public init(
    artifacts: [ArtifactReference],
    diagnostics: [DesignDiagnostic] = [],
    provenance: ExecutionProvenance
  ) {
    self.artifacts = artifacts
    self.diagnostics = diagnostics
    self.evidence = EvidenceManifest(
      provenance: provenance,
      artifacts: artifacts
    )
  }
}

/// Protocol seam for DRC/LVS/PEX/signoff adapters that use this support
/// package for process safety while returning Foundation evidence.
public protocol SignoffToolEngine: Engine
where Request == SignoffToolRequest, Output == SignoffToolResult {}
