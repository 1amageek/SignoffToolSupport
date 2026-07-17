# SignoffToolSupport Requirements

## Required capabilities

| ID | Requirement |
|---|---|
| STS-001 | Build independently without a domain-engine or flow-runtime dependency. |
| STS-002 | Expose typed process execution with stdout, stderr, and exit status. |
| STS-003 | Allow domain engines to inject cancellation checks without importing flow state. |
| STS-004 | Keep generic signoff request, result, evidence, and verdict contracts in their owning domain packages. |
| STS-005 | Preserve typed timeout, launch, cancellation, and process-tree cleanup behavior. |
| STS-006 | Reject invalid timeout/grace configurations before launching an external process. |
| STS-007 | Resolve PDK files from profile data with safe relative-path checks and explicit missing-asset diagnostics. |
| STS-008 | Keep readiness and semantic inventory reports deterministic and machine-readable. |
| STS-009 | Leave DRC/LVS/PEX rule semantics and qualification decisions to their owning packages. |

## Quality and acceptance criteria

- `swift build` succeeds in the package checkout.
- The current regression baseline remains green: 37 tests pass through the
  timeout-bounded Xcode package scheme.
- A process cancellation or timeout must terminate the complete process group,
  not only the direct child.
- Process execution status remains distinct from every domain signoff verdict
  and qualification decision.

## Non-goals

- No DRC/LVS/PEX/STA/EM-IR algorithms or foundry-rule interpretation.
- No tool registry or trust-level evaluator.
- No project/run ledger, approval state, or UI state.
- No adapter that silently converts an unqualified tool output into a passing
  signoff result.

## Next-agent acceptance gate

An implementation agent is complete when its implementation conforms directly
to the owning domain protocol, routes external launches through
`TimedProcessRunner`, emits the domain's reproducible Foundation-backed result,
and preserves the fail-closed behavior documented above.
