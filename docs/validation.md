# Validation and exact-source evidence

## Inventory

| Layer | Inventory | Interpretation |
| --- | --- | --- |
| Extended conformance | 144 conversion, 40 typing, 7 environment vectors; 16 inherited controls | Preserve existing main behavior; the successor overflow control now expects `Index_overflow`. |
| OCaml typing refusal classification | 7 injected controls | Wrong-binder cases require `Type_mismatch`; other semantic errors, resource failures and successful inference cannot satisfy them. |
| OCaml definition checks | 55 outcome-classification, 8 corpus-integrity and 27 snapshot-preservation controls | Exact rejection causes, fixed sequence and preservation of prior bindings/snapshots after refusal. |
| Rust baseline | 19 rows: 9 matching equality, 2 designated disagreements, 4 WHNF, 4 substitution | Finite trusted-oracle contract, including its limits. |
| Harness rejection | 12 controls | Missing/duplicate rows, malformed expressions and altered/unregistered disagreements are rejected. |
| OCaml adversarial | 75 named controls | Scope, capture, cyclic values, sharing, negative integers, overflow, erased invalid children, divergence and intermediate height. |
| Explicit disagreements | 2 controls | η and proof irrelevance remain outside conversion. |
| Generated properties | 1,024 cases and 10,240 assertions | Internal scoped-syntax properties; not Lean-checked and not necessarily well typed. |
| Reference batch concurrency | 53 controls, 32 generated DAGs, 3,309 assertions | Same waves, immutable environment observations and exact errors at 1/2/4/8 workers; real overlapping domain execution. |
| Domain startup failure | 9 assertions in a separate executable | Injected second-spawn failure joins the active worker, runs its exit hook and leaves the pool reusable. |
| Optional concurrency benchmark | Wide and chained workloads at 1/2/4/8 workers | Every result and wave sequence matches the sequential reference; wall/CPU times are observations, with no speed threshold. |
| Fresh Lean regeneration | Four fixture files from two generators | Pinned trusted execution must reproduce exact fixture bytes. |
| Strict Lean typing replay | All 40 typing rows: 26 accepted and 14 exact semantic refusals; 5 injected classifier controls | Nine wrong-binder cases require `appTypeMismatch`; time, memory, recursion, interruption and internal failures cannot count as typing evidence. |
| Strict Lean definition replay | All 7 environment rows: 2 accepted definitions, 4 exact semantic refusals and 1 final inference; 5 injected classifier controls | Checked insertion, designated exceptions, retained earlier bindings and absence of refused fresh names. |
| Provenance | Seven source artifacts | Revisions, paths, Git blob identity, SHA-256 and toolchain pins. |
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
python3 tools/acceptance.py --lean --benchmark --audit /absolute/path/to/audit_estate_layout.py
```

`OCAMLC` and `LEAN` can supply absolute executable paths. The runner makes the
selected Lean available to its child processes as well. Missing tools, wrong
versions, generation failures and byte differences produce errors. Without a
local auditor argument, the wrapper fetches the pinned canonical auditor and
checks its digest before execution. The publication-session toolchains were
restored from the pinned compiler source and the exact Lean release; the
receipt records the versions actually executed.

The optional benchmark runs five repetitions of each 128-definition workload
at every worker count. Its log hash, command and timestamps are included in the
same receipt when requested. Results concern the synthetic bytecode reference
workloads, not a speedup of upstream Lean. See the
[concurrency guide](reference-concurrency.md) for timing boundaries.

## Boundaries

All OCaml input children are validated before erasing reductions. OCaml resource
refusals never count as inequality or expected typing/definition rejection.
The supplementary Lean checkers require the designated semantic exception for
every negative typing and definition row; each validator's five classifier
controls inject exceptions rather than induce actual resource exhaustion.
Height in the OCaml reference is limited to
128 (leaf height one), including constructed intermediates and active evaluator
contexts. Work units are implementation-specific. `Limit_exceeded` also covers
the defensive runtime stack-overflow handler, so it does not prove divergence.
Bare conversion refuses constants even if a reduction would erase them.

η, proof irrelevance, general universes, inductives, quotients, `.olean` import
and declaration/theorem admission are unsupported. The retained reference
inference/environment subsystem is not a general Lean kernel. Neither finite
agreement nor estate layout conformance proves complete compatibility.

The byte-preserved `Generate.lean` still accepts generic exceptions for its
negative rows. Its output alone is insufficient to establish the intended
semantic refusal. `ValidateTypingRefusals.lean` and
`ValidateDefinitionRefusals.lean` independently replay those same fixtures
and require their precise rejection causes. The definition checker uses
normal checked Lean insertion; it adds no OCaml admission authority. See
[definitions-v1](../schemas/definitions-v1.md) for the exact four-case mapping.

The concurrency increment starts from main
`986874105d0136e7fca4440eb4392eba75cce6f8` and replaces the earlier receipt with
a fresh run over the changed source and documentation. The fixture inventory
remains 210 unique rows:
191 extended OCaml rows plus the 19-row Rust baseline, including its two
declared disagreements. Supplementary replays do not increase that fixture
count. The receipt's baseline revision is the local checkout parent;
`conformance/provenance.json` records it separately from the historical
dependent-typing integration and original imported artifact revisions.
