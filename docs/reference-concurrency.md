# Bounded concurrency for reference definitions

Status: implemented candidate reference on the baseline of merged PR #4,
`986874105d0136e7fca4440eb4392eba75cce6f8`. Acceptance authority remains false.
Draft PR #5's separate generator-outcome changes are not prerequisites.

## Decision

Parallelize independent transparent-definition checks with OCaml 5 domains.
Keep the existing typing, substitution, reduction and fuel rules. Derive a
dependency graph from the actual expressions, check ready definitions against
one immutable environment snapshot, then combine only checked sibling branches.

The implementation uses only the pinned OCaml distribution. The reference
modules do not depend on Unix; conformance deadlines and benchmark timing use
its bundled Unix library. Native compilation and third-party task libraries
are not required.

| Component | Responsibility |
| --- | --- |
| `reference/bounded_parallel.ml` | Bounded domain group, ordered results and complete worker cleanup. |
| `reference/definition_batch.ml` | Bounded dependency discovery, deterministic waves and transactional results. |
| `Conversion.merge_checked_branches` | Exact parent-snapshot and unique-name checks over already checked closed values. |
| `conformance/batch.ml` | Sequential/parallel comparisons and adversarial scheduling/merge controls. |
| `conformance/pool_start_failure.ml` | Injected second-spawn failure after one worker starts; verifies cleanup. |
| `conformance/benchmark.ml` | Wide-workload and dependency-chain measurements with result equivalence checks. |

See [the batch contract](../schemas/definition-batch-v1.md) for error precedence,
bounds, forward references and the distinction from ordered definition replay.

## Example

The caller may list dependents before their prerequisites. This example reports
two waves, `[["A"]; ["Identity"]]`:

```ocaml
let definitions : Definition_batch.definition list = [
  { name = "Identity";
    ty = Conversion.Pi (Conversion.Const "A", Conversion.Const "A");
    value = Conversion.Lam (Conversion.Const "A", Conversion.Var 0);
    fuel = 100_000 };
  { name = "A"; ty = Conversion.Sort 1; value = Conversion.Sort 0;
    fuel = 100_000 };
]

let result =
  Definition_batch.run ~workers:4 ~scan_fuel:100_000 ~merge_fuel:100_000
    Conversion.empty_environment definitions
```

`Ok report` describes successful reference checking for the entire batch.
`Error` supplies no partially extended environment. Both one-worker and
multi-worker runs use the same snapshots and operation budgets.

## Correctness evidence

The retained conformance runner still regenerates the four existing fixture
files with the pinned Lean version and replays exact typing/definition refusals.
The new batch controls add 53 named cases, 32 deterministic generated dependency
graphs and 3,309 assertions. They compare 1, 2, 4 and 8 workers, including small
fuel budgets, and cover malformed graphs, hidden dependencies, immutable
snapshots, invalid sibling merges and exact error selection.

An atomic barrier demonstrates actual overlap on distinct domains, with a
finite deadline to fail a serial regression. A separate executable injects a
failure during the second spawn after the first worker becomes active. Its
nine assertions check callback completion, the worker exit hook, live-domain
count and subsequent pool usability. This is controlled failure injection,
not an attempt to exhaust the host.

These tests are finite observations. They do not prove a general scheduler
refinement theorem, full environment correspondence or Lean kernel compatibility.
The original Lean corpus tests the existing checking fragment; the new generated
dependency graphs are OCaml controls and have no additional Lean theorem claim.

## Performance measurements

```sh
make benchmark
make benchmark BENCHMARK_ARGS='--scale 4 --repetitions 5'
make acceptance-benchmark ESTATE_AUDITOR=/absolute/path/to/audit_estate_layout.py
```

The wide workload has independent definitions with beta reduction and type-tree
checking. The chain workload has one ready definition per wave. Both run at
1, 2, 4 and 8 workers. The benchmark checks every resulting environment
structurally and compares the exact wave sequence against a one-worker result.
No timing ratio can make an incorrect result pass.

Reported wall and process CPU times include dependency planning, checking,
domain startup/join and merging. Fixture construction, a full collection before
each sample and result comparisons are outside the timed interval. Times are
means over the requested repetitions. Process CPU time and CPU/wall ratio help
distinguish actual parallel execution from ordinary timing variation.

`make acceptance-benchmark` records five repetitions of each 128-definition
workload and binds `benchmark.log` to the same source digest as the correctness
logs. There is no minimum-speedup gate. The benchmark is synthetic, uses
bytecode, and does not measure Lean elaboration, real project builds or native
OCaml performance. The independent workload can scale; a dependency chain has
no checking parallelism to expose. Creating domains per wave adds overhead
when waves are small.

## Next obligations

The [direct bytecode comparison](bytecode-optimization.md) adds an actual Lean
kernel baseline and distinct, unshared and dependent workloads. Scoped successful
checking caches and retained constant types reduce repeated work while preserving
the old logical fuel accounting. Its complete results bound the scope of any
performance claim; extra workers cannot create parallel checking in a chain.

Measure representative exported proof/reference workloads before changing pool
lifetime, adding shared caches or parallelizing individual reductions. A persistent
pool should justify its extra lifecycle complexity with measured startup costs.
Any future extension that retains unresolved names must re-establish the checked
merge argument. General declaration admission needs its own correspondence and
authority decision independently of performance results.
