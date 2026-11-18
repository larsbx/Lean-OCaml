# OCaml bytecode checking against Lean

## Source and evidence

This increment reduces repeated checking work in the bounded OCaml reference
and compares it directly with Lean 4.34.1's actual native kernel. OCaml remains
5.5.1 bytecode throughout. `acceptance_authority = false` is unchanged.

The unpublished November 17 working copy was unavailable when the authorized
publication resumed. The implementation and benchmark tooling were restored
from the code recorded in the conversation, starting from merged main
`d2e2bdf63a49b75ba2091132613fcf88b76a183e`. This reconstruction has a new source
identity. Earlier unpublished hashes and measurements are historical reports;
they are not evidence for the reconstructed files. All receipts and results
published with this increment are freshly generated from the current source.

## Results

<!-- measured-results-start -->
Fresh seven-sample measurements are pending. This section will be populated
from the final measurement receipt before merge.
<!-- measured-results-end -->

The original wide and identity fixtures repeat one physically shared type/value
pair across 128 different names. They can share a successful checking judgment,
while every name, duplicate lookup, fuel budget and insertion is still checked.
They form one checking group even with an eight-worker limit. Any win on those
fixtures is primarily removal of repeated work. Every timed batch starts with
empty checking caches.

The four additional families are supplemental controls used during tuning,
not representative Lean-project measurements or an untouched validation set.
Distinct and unshared trees have pairwise distinct normal forms. The unshared
family also has no cross-definition input-node sharing. Results for all families
and all requested worker counts are retained, including losses.

## Implementation

Successful imports and dependency scans cache validated subtree results and
original logical charges. Private terms retain checked height, free-variable
bounds and deterministic hashes; bottom-up interning coalesces equal private
subterms after input validation. Inference keys include open-term context
identity and evaluator depth. Head and normalization caches retain depth.
Simple leaves bypass cache machinery when direct evaluation is cheaper.
Beta/zeta tail continuations remain tail calls.

A cache hit spends the complete original logical charge. If that charge cannot
fit the remaining fuel, the original traversal runs to preserve the refusal
reached at that budget. Failed computations do not establish cached success.
Bounded direct-mapped public-expression and group indexes discard reuse on
collisions rather than growing collision chains.

Accepted constants retain their checked normalized type and original inference
charge. Constant expansion can reuse this evidence instead of re-inferring a
large expanded body. Values remain closed and contain no unresolved names.
Environments contain immutable entries, a persistent name index and their size.
A found name spends `size - insertion_ordinal`; an absent name spends `size + 1`.
These are exactly the old list-lookup charges.

Complete successful judgments may be reused only within a checker bound to one
parent snapshot. A separate bounded annotation cache may cross joined waves
inside a batch only when actual original-syntax import observed no constant,
including in children that reduction erases. Import, type checking and
normalization charges replay at their original stages around value checking.
Each group exclusively owns its cache slot until the workers join. No cache
survives a subsequent `Definition_batch.run` call.

Singleton waves and single groups execute directly. Other groups use the
existing bounded domain pool. Groups partition result positions, giving each
slot one writer; the caller reads results after joining. Input-order failures
and insertion order remain deterministic. A nonempty merge creates fresh
entries, including a singleton merge, preserving exact parent-tail identity.
A singleton may reuse the branch's immutable name index.

Sources: [checker](../reference/conversion.ml),
[public interface](../reference/conversion.mli),
[batch planner](../reference/definition_batch.ml), and
[batch contract](../schemas/definition-batch-v1.md).

## Workloads

All comparisons use 128 definitions and the same DAG fixture bytes in both
drivers. Each indexed node is constructed once, preserving encoded physical
sharing on both sides.

| Family | Construction |
| --- | --- |
| `wide` | 128 names with the same depth-nine shared binary Pi body and beta-wrapped annotation; 9,215 expanded body nodes |
| `chain` | Same first body, followed by aliases of the predecessor; 128 serial waves |
| `identities` | Repeated identity lambda and Pi annotation; three nodes each |
| `distinct_trees` | Pairwise distinct normal forms with shared subtrees and asymmetric motifs; at most 11,519 expanded body nodes |
| `unshared_trees` | Pairwise distinct normal forms, separately constructed syntax, no cross-definition sharing; at most 447 body nodes |
| `dependent_terms` | Polymorphic projections under 1–24 value binders, with beta applications and typed lets |
| `alias_diamonds` | 32 distinct base/left/right/join dependency diamonds in three waves |

The original three fixture hashes match the recorded November 17 inputs exactly.
The [generator](../tools/optimization_workloads.py) supplies machine-readable
inventories and four explicit semantic-refusal specimens.

## Timing and validation

The runner freshly compiles both drivers before measuring. OCaml uses only
`ocamlc`; each process must report `Sys.backend_type = Bytecode`. The custom
runtime links a small C monotonic-clock stub. Checking is entirely bytecode.
Lean uses release 4.34.1 at `5045d0056413266e57c625dcd7c365b10e377c52`, with its
bundled `leanc -O3` driver and native kernel. It starts from `mkEmptyEnvironment 0`
and invokes `env.addDeclCore 10000000 1000 declaration none true`, explicitly
checking safe transparent monomorphic definitions at trust level zero.

There are seven samples per workload/configuration, with OCaml worker limits
1, 2, 4 and 8 and one synchronous Lean insertion loop. Untimed calibration
targets 150 ms of measured work per sample. Configuration order is shuffled
deterministically, with one measurement process at a time. The workspace is
not an isolated benchmark server; ranges and host details are recorded.

Both timers are monotonic. OCaml includes planning, public-syntax validation,
checking, domain startup/join and merging. Lean includes its complete ordered
checked-insertion loop. Parsing, construction, process startup, compilation,
verification and OCaml's full major GC before each batch are untimed. GC during
checking remains timed. These are warm-process batch costs rather than whole
process or project-build times. Lean's fixture reader also checks name
uniqueness and absence of loose bound variables before timing.

Each batch starts from an empty environment. Every timed OCaml result must
match the complete checked environment and exact waves of a separate one-worker
reference; accepted binding types are also verified. Each Lean result must
preserve names, types, values and safety flags, followed by kernel inference
and conversion checks. Both drivers require a deliberately ill-typed sort
definition to fail with the exact semantic mismatch before timing.

The receipt records every calibration, sample, iteration count, source hash,
fixture hash, toolchain hash and binary hash. Source changes during measurement
invalidate the run. The [OCaml driver](../conformance/benchmark_compare.ml),
[Lean driver](../oracles/BenchmarkKernel.lean),
[clock stub](../conformance/benchmark_clock.c), and
[runner](../tools/compare_lean.py) make the timing boundaries reviewable.

## Acceptance

The differential gate compiles the six hash-verified baseline reference files
from merged main beside the current modules. It compares exact successful
results and refusal constructors over fuel grids and boundary budgets, cache
contexts/collisions, hidden constants, hostile scopes/heights/cycles, indexed
name positions, historical snapshots, merge freshness and worker counts.
Actual control/assertion counts are recorded in the current log. This is finite
regression evidence, not an independent soundness proof.

Full acceptance retains the existing 210 fixture rows, adversarial/generated
checks, batch concurrency checks, injected worker-start cleanup checks, strict
Lean semantic-refusal replays, byte-for-byte regeneration of all four Lean
fixture files and the pinned estate audit. The receipt binds the complete
source tree and log hashes. See [acceptance.json](../conformance/evidence/acceptance.json),
[conformance.log](../conformance/evidence/conformance.log), and
[validation guide](validation.md).

## Reproduce

```sh
export OCAMLC=/path/to/ocaml-5.5.1/bin/ocamlc
export LEAN=/path/to/lean-4.34.1/bin/lean
python3 tools/compare_lean.py \
  --samples 7 --definitions 128 --workers 1 2 4 8 \
  --min-sample-seconds 0.15 \
  --workloads wide chain identities distinct_trees unshared_trees dependent_terms alias_diamonds \
  --output conformance/evidence/bytecode-optimization
make acceptance ESTATE_AUDITOR=/absolute/path/to/audit_estate_layout.py
```

Use full Git history, or provide the verified baseline checkout through
`OPTIMIZATION_BASELINE`. Results are in
[results.json](../conformance/evidence/bytecode-optimization/results.json) and
[run.log](../conformance/evidence/bytecode-optimization/run.log), alongside all
seven identical input fixtures.

## Scope

A win on repeated definitions does not establish a general advantage over Lean.
This reference implements bounded transparent definitions, numeric universes
and beta/zeta conversion. General universes, inductives, recursors, quotients,
eta, proof irrelevance, `.olean` import and full declaration/theorem admission
remain outside it. These experiments do not measure elaboration, tactics,
Mathlib or whole-project builds. Fresh syntax import/interning and dependent
terms remain concrete optimization targets; their costs cannot all be removed
by reusing complete judgments or adding workers.
