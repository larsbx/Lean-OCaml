# Validation and exact-source evidence

## Inventory

| Layer | Inventory | Interpretation |
| --- | --- | --- |
| Inherited conformance | 144 conversion, 13 typing, 7 environment vectors; 16 controls | Preserve existing main behavior; the successor overflow control now expects `Index_overflow`. |
| Rust baseline | 19 rows: 9 matching equality, 2 designated disagreements, 4 WHNF, 4 substitution | Finite trusted-oracle contract, including its limits. |
| Harness rejection | 12 controls | Missing/duplicate rows, malformed expressions and altered/unregistered disagreements are rejected. |
| OCaml adversarial | 75 named controls | Scope, capture, cyclic values, sharing, negative integers, overflow, erased invalid children, divergence and intermediate height. |
| Explicit disagreements | 2 controls | η and proof irrelevance remain outside conversion. |
| Generated properties | 1,024 cases and 10,240 assertions | Internal scoped-syntax properties; not Lean-checked and not necessarily well typed. |
| Fresh Lean regeneration | Four fixture files from two generators | Pinned trusted execution must reproduce exact fixture bytes. |
| Provenance | Seven source artifacts | Revisions, paths, Git blob identity, SHA-256 and toolchain pins. |
| Estate layout | Pinned external auditor | Local manifest/layout conformance only. |

Counts are inventory. Actual results are recorded in
`conformance/evidence/acceptance.json` and its accompanying logs. The receipt
separates the baseline Git revision from the SHA-256 of all local source files,
records tool versions and paths, hashes logs, and checks source stability during
acceptance. `source-manifest.json` lists every source path, length and hash.
The receipt is unsigned local evidence, not an independent attestation or a
hosted CI result. Compare source hashes before applying it to another tree.

The evidence directory is excluded from its own source digest to avoid
self-reference. Build outputs and Git metadata are also excluded. Symlinked
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

All input children are validated before erasing reductions. Resource refusals
never count as inequality or expected typing rejection. Height is limited to
128 (leaf height one), including constructed intermediates and active evaluator
contexts. Work units are implementation-specific. `Limit_exceeded` also covers
the defensive runtime stack-overflow handler, so it does not prove divergence.
Bare conversion refuses constants even if a reduction would erase them.

η, proof irrelevance, general universes, inductives, quotients, `.olean` import
and declaration/theorem admission are unsupported. The retained reference
inference/environment subsystem is not a general Lean kernel. Neither finite
agreement nor estate layout conformance proves complete compatibility.

The earlier local review tree was restored for publication and revalidated;
its old receipt is not transferred to the new source. PR #2's separate 27
binder-typing vectors are outside this increment. Its later integration must
update both source provenance and the 13-case typing count.
