# Validation and exact-source evidence

## Inventory

| Layer | Inventory | Interpretation |
| --- | --- | --- |
| Extended conformance | 144 conversion, 40 typing, 7 environment vectors; 16 inherited controls | Preserve existing main behavior; the successor overflow control now expects `Index_overflow`. |
| OCaml typing refusal classification | 7 injected controls | Wrong-binder cases require `Type_mismatch`; other semantic errors, resource failures and successful inference cannot satisfy them. |
| Rust baseline | 19 rows: 9 matching equality, 2 designated disagreements, 4 WHNF, 4 substitution | Finite trusted-oracle contract, including its limits. |
| Harness rejection | 12 controls | Missing/duplicate rows, malformed expressions and altered/unregistered disagreements are rejected. |
| OCaml adversarial | 75 named controls | Scope, capture, cyclic values, sharing, negative integers, overflow, erased invalid children, divergence and intermediate height. |
| Explicit disagreements | 2 controls | η and proof irrelevance remain outside conversion. |
| Generated properties | 1,024 cases and 10,240 assertions | Internal scoped-syntax properties; not Lean-checked and not necessarily well typed. |
| Fresh Lean regeneration | Four fixture files from two generators | Pinned trusted execution must reproduce exact fixture bytes. |
| Strict Lean typing replay | All 40 typing rows: 26 accepted and 14 exact semantic refusals; 5 injected classifier controls | Nine wrong-binder cases require `appTypeMismatch`; time, memory, recursion, interruption and internal failures cannot count as typing evidence. |
| Definition replay | 2 insertions, 4 exact semantic refusals, 1 inference; 40 Lean and 55 OCaml outcome controls, 8 OCaml corpus controls | Ordered [definition outcomes](../schemas/definitions-v2.md) must agree with the designated categories. Prior environments survive refusal. |
| Provenance | Five byte-identical imports and two derived artifacts | Immutable origins, local Git blob IDs and SHA-256 hashes, and toolchain pins. |
| Source receipt regression checks | 3 Python tests | Checkout/worktree metadata produce the same source hash; source file and directory symlinks are refused. |
| Estate layout | Pinned external auditor | Local manifest/layout conformance only. |

Counts are inventory. Actual results are recorded in
`conformance/evidence/acceptance.json` and its accompanying logs. The receipt
separates the baseline Git revision from the SHA-256 of all local source files,
records tool versions and paths, hashes logs, and checks source stability during
acceptance. `source-manifest.json` lists every source path, length and hash.
The receipt is unsigned local evidence, not an independent attestation or a
hosted CI result. Compare source hashes before applying it to another tree.

The evidence directory is excluded from its own source digest to avoid
self-reference. Build outputs and Git metadata (including a worktree's `.git`
file) are also excluded. Symlinked
source files and directories are refused. An extracted source bundle has no
Git baseline but can still produce byte-level evidence; Git must be installed.

## Reproduction

Requirements: OCaml 5.5.1, Python 3.11+, Git, POSIX shell and `diff`; trusted
regeneration additionally requires Lean 4.34.1 at commit
5045d0056413266e57c625dcd7c365b10e377c52. No third-party OCaml packages, Dune,
Opam or native compiler are needed. The existing CI workflow records the
SHA-512-pinned compiler source/build recipe.

```sh
sh conformance/run.sh
sh conformance/run.sh --lean
sh tools/estate-audit.sh /absolute/path/to/audit_estate_layout.py
python3 tools/acceptance.py --lean --audit /absolute/path/to/audit_estate_layout.py
```

`OCAMLC` and `LEAN` can supply absolute executable paths. The runner makes the
selected Lean available to its child processes as well. Missing tools, wrong
versions, generation failures and byte differences produce errors. Without a
local auditor argument, the wrapper fetches the pinned canonical auditor and
checks its digest before execution. The publication-session toolchains were
restored from the pinned compiler source and the exact Lean release; the
receipt records the versions actually executed.

## Boundaries

All OCaml input children are validated before erasing reductions. OCaml resource
refusals never count as inequality or expected typing rejection. The supplementary
Lean checker requires the designated semantic exception for every negative
typing row; its five classifier controls inject exceptions rather than induce
actual resource exhaustion. Height in the OCaml reference is limited to
128 (leaf height one), including constructed intermediates and active evaluator
contexts. Work units are implementation-specific. `Limit_exceeded` also covers
the defensive runtime stack-overflow handler, so it does not prove divergence.
Bare conversion refuses constants even if a reduction would erase them.

η, proof irrelevance, general universes, inductives, quotients, `.olean` import
and declaration/theorem admission are unsupported. The retained reference
inference/environment subsystem is not a general Lean kernel. Neither finite
agreement nor estate layout conformance proves complete compatibility.

The definition lane checks the return from pinned Lean's checked
[`Environment.addDeclCore`](https://github.com/leanprover/lean4/blob/5045d0056413266e57c625dcd7c365b10e377c52/src/Lean/Environment.lean).
Controls cross-check the four observed semantic errors, exercise a separate
`funExpected` failure and force real `deepRecursion` with a low recursion
budget. Injected timeout, memory, interruption and `other` exceptions also
fail to satisfy any expected refusal. The `other` payload repeats each expected
tag to guard against message matching. OCaml uses a real zero-fuel
`Limit_exceeded` result and injects incompatible semantic and bounded-reference
errors into the same matcher used by fixture replay.

All four fixture files are regenerated. The 210-row inventory includes
191 extended rows and the 19-row Rust baseline, including its two declared
disagreements. The regenerate-and-compare gate checks the new definition tags
against the committed fixture. `conformance/provenance.json` preserves the
original generator and corpus identities alongside the new local digests.
