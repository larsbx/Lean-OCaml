# ADR 0002: Harden bounded conversion and publish the reviewed increment

Status: implemented candidate reference; publication and merge authorized by
the user on November 14, 2026. Acceptance authority is unchanged.

## Decision

Extend the existing `Lean-OCaml` implementation at main
`802d30bc90859e82faf33049513fd82f7e507eb6`. Preserve its closed conversion,
reference typing and transparent-definition interfaces. Add explicit scoped
operations, checked input/intermediate heights, metered structural comparison,
separate height/arithmetic refusals, and the original 19-row Rust oracle corpus.

Use private height-annotated immutable terms after validating the public OCaml
syntax. This prevents cyclic public values and unchecked intermediate growth
from bypassing the resource contract. No pointer identity shortcut is used.

Keep two known directional disagreements explicit: η and proof irrelevance
remain outside β/ζ conversion. Generated OCaml properties support internal
regression checking and are not represented as trusted Lean evidence.

## Sources and authority

The Rust baseline is `27ececb284b82b7d43884af317c7fcb89feb3da0`; Lean is 4.34.1
at `5045d0056413266e57c625dcd7c365b10e377c52`; OCaml is 5.5.1. The exact
source mappings and hashes are recorded in `conformance/provenance.json`.
The copied Lean generator is attributed non-authoritative oracle source,
reused at the user's request. It is not vendored runtime implementation.

Keep the canonical estate auditor external, pinned to governance revision
`bd731398b567cfe523667fc8e23a96d299067141` and SHA-256
`412a64dea58d709aae21e5a0315b8e7e96488c310a9d999267927ba3d8146a30`.
A layout-audit pass changes neither estate registration nor mathematical
acceptance. Implementation stays in `reference/`; `acceptance_authority` is
false and the unimplemented admission boundary remains in `kernel/`.

## Publication and validation

The earlier temporary local review workspace was unavailable in the later
publication session. The branch was restored from the recorded implementation
and pinned upstream sources, then freshly validated. The earlier source digest
is historical and is not reused as evidence for the restored tree. The new
receipt identifies its exact bytes and current tool paths.

The user's later PR-and-merge instruction supersedes the earlier local-only
publication restriction. Keep the independent dependent-typing PR #2 separate.
Require the conformance workflow to pass at the proposed head, then merge with
an expected-head guard. Document local and hosted evidence separately.

Successful tests establish finite observations only. Full Lean compatibility,
a general program-refinement theorem, declaration admission and performance
superiority remain unproved and unclaimed.

## Subsequent integration

The separate dependent-typing cases are integrated by [ADR 0003](0003-dependent-typing-integration.md)
after this conversion-hardening increment merged. Its fresh receipt and source
provenance supersede the earlier inventory for the resulting combined tree.
