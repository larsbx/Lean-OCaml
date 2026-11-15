# ADR 0004: Require precise reference-definition refusal evidence

Status: implemented candidate reference. The canonical repository is
`larsbx/Lean-OCaml`; acceptance authority remains false.

## Problem

The seven-row definition corpus contains two accepted definitions, four
rejections and one inference observation. The inherited Lean generator accepts
any kernel exception for a negative row. The OCaml replay likewise accepted
several semantic errors interchangeably. A resource error on the Lean side, or
the wrong semantic error on either side, could therefore be mistaken for the
intended refusal. PR #2 closed this gap for typing and explicitly left the
definition cases open.

## Decision

Start from main `08340ce24bcdbb6c8563152a7ea640406d67887b`. Keep all seven
imported source artifacts byte-identical and keep the reference core and its
public interfaces unchanged. Add a separate Lean definition validator and make
the OCaml replay require the exact sequence and exact refusal policy for every
definition row.

| Fixture | OCaml error | Lean kernel exception |
| --- | --- | --- |
| Duplicate `ocamlRefAlias` | `Duplicate_definition` | `alreadyDeclared` |
| Self-reference `ocamlRefMissing` | `Unknown_constant` | `unknownConstant` |
| Annotation mismatch `ocamlRefMismatch` | `Type_mismatch` | `declTypeMismatch` |
| Invalid annotation `ocamlRefNonType` | `Expected_sort` | `typeExpected` |

These are exact expectations for these fixtures. They do not prescribe error
precedence for arbitrary invalid declarations. Unexpected success, a different
semantic error, or any resource/internal refusal fails the observation.

The trusted validator uses ordinary checked Lean kernel insertion. It verifies
the final inference against an independently checked expected type and checks
prior successful bindings after insertion attempts. Both replays exercise
immutable snapshots and absence of refused fresh names. No unchecked insertion,
caller-supplied verdict or generic-error acceptance supplies evidence.

## Verification and provenance

The additional checks are wired into the existing acceptance command. Named
OCaml controls cover each refusal policy against alternate API outcomes,
malformed corpus sequences and prior-snapshot observations. Lean controls
reject injected timeout, memory, recursion, interruption and internal
exceptions. Injection tests validate classification; they do not establish
whole-process resource isolation.

Fresh local acceptance compiles with OCaml 5.5.1, replays the 210 existing
fixture rows and all retained adversarial/property controls, executes both
strict Lean validators, regenerates all four fixture files under Lean 4.34.1,
checks the seven copied artifact identities, and runs the pinned external
estate auditor. The receipt records actual results and the complete source
digest. Baseline hosted success is historical evidence for its exact source;
new hosted results must be reported independently.

The provenance manifest records the current baseline separately from the
historical dependent-typing integration parents and from each imported
artifact's original revision. The new validator is original repository source
covered by the receipt, not another copied upstream artifact.

## Authority and remaining work

The Lean oracle imports `Init` and checks fresh named monomorphic definitions.
The OCaml environment models transparent definitions in its existing bounded
fragment. Agreement on these observations does not identify the complete
environments or constitute a general environment-correspondence theorem.

The kernel admission boundary remains unimplemented. No theorem admission,
general universes, opaque or recursive definitions, inductives, quotients, η
or proof irrelevance are introduced. The next semantic extension requires its
own mapping and trusted positive/refusal evidence; no capability follows
merely from passing this suite.
