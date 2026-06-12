# SignoffToolSupport

Shared non-domain support for signoff tools (Magic, Netgen, ngspice adapters in the
engine packages). Nothing here knows about DRC, LVS, or PEX semantics.

## Types

| Type | Responsibility |
|---|---|
| `TimedProcessRunner` | Process execution with mandatory timeout and descendant process-tree cleanup on cancel/timeout — a hung child never outlives the run |
| `Sky130PDKLocator` | Discovers the Sky130 PDK root on the local machine |

## Rules

- Every external tool launch goes through `TimedProcessRunner`; invalid timeouts are
  rejected before launch, and cancellation kills the whole process tree, not just
  the parent.

## Build & test

```bash
swift build
swift test
```
