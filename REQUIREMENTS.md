# SignoffToolSupport Requirements

## Required capabilities

| ID | Requirement |
|---|---|
| STS-001 | Build independently with a local `CircuiteFoundation` dependency. |
| STS-002 | Expose `SignoffToolEngine` as the shared asynchronous adapter boundary. |
| STS-003 | Keep `SignoffToolRequest` and `SignoffToolResult` `Sendable`, `Hashable`, and `Codable`. |
| STS-004 | Require digest-bearing Foundation artifact references at the cross-package boundary. |
| STS-005 | Preserve typed timeout, launch, cancellation, and process-tree cleanup behavior. |
| STS-006 | Reject invalid timeout/grace configurations before launching an external process. |
| STS-007 | Resolve PDK files from profile data with safe relative-path checks and explicit missing-asset diagnostics. |
| STS-008 | Keep readiness and semantic inventory reports deterministic and machine-readable. |
| STS-009 | Leave DRC/LVS/PEX rule semantics and qualification decisions to their owning packages. |

## Quality and acceptance criteria

- `swift build` succeeds in the package checkout.
- The current regression baseline remains green: 33 tests pass under
  `swift test --parallel`.
- A process cancellation or timeout must terminate the complete process group,
  not only the direct child.
- A result must distinguish process execution status from signoff qualification
  and must not claim approval without external evidence.
- Artifact references must be created from materialized files and preserve
  byte-count and digest integrity metadata.

## Non-goals

- No DRC/LVS/PEX/STA/EM-IR algorithms or foundry-rule interpretation.
- No tool registry or trust-level evaluator.
- No project/run ledger, approval state, or UI state.
- No adapter that silently converts an unqualified tool output into a passing
  signoff result.

## Next-agent acceptance gate

An implementation agent is complete when its domain adapter conforms to
`SignoffToolEngine`, routes launches through `TimedProcessRunner`, emits a
reproducible Foundation-backed result, and preserves the fail-closed behavior
documented above.
