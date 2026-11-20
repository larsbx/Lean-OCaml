# Goose in the Lean kernel migration benchmarks

This experiment adds [aardappel/goose](https://github.com/aardappel/goose) as a
measured candidate alongside OCaml 5.5.1 bytecode and Lean 4.34.1's actual native
kernel. The implementation is a bounded sequential checker for the shared
transparent-definition fragment. It has **no declaration or theorem admission
authority** and is not a complete Lean kernel migration.

The measured pilot is promising: Goose has substantially lower median checked
batch times than Lean on six of seven families, and effectively ties Lean on
fresh unshared trees. It is faster than every measured OCaml bytecode worker
configuration. The gains support continuing the bounded migration experiment;
they do not establish a general language advantage or full-kernel compatibility.

## Results

<!-- measured-results-start -->
Measurements started November 19, 2026 at 23:35 EST and passed all **294
samples across 42 configurations**, plus 42 calibration samples.
Every one of the **203,483 timed batches / 26,045,824
declaration insertions** passed its result checks. The independent gate passed
**964 ordered outcomes per engine**, including the two registered conversion
differences, and all six Goose parser/structural/resource controls.

All 19 measured source hashes match published implementation commit `9a6c54f961ddb6b8f6a9b0020a6265cde913fdba`;
the [source identity receipt](../conformance/evidence/goose-comparison/source-correspondence.json)
binds that check to the measurement receipt. Measured sources stayed unchanged.

The shared host reported INTEL(R) XEON(R) PLATINUM 8573C, 9 CPUs in the affinity mask,
and `Linux-6.18.57-x86_64-with-glibc2.41`. The emitted Goose checker used GCC 14.2.0.

### Median milliseconds per 128-definition checked batch

Smaller values are faster. Every entry is the median of seven sample averages.
Goose and Lean are single-worker native executables; OCaml remains bytecode.

| Workload | Lean native | Goose AOT | OCaml 1 | OCaml 2 | OCaml 4 | OCaml 8 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `wide` | 2.936 | 0.022 | 0.544 | 0.540 | 0.577 | 0.537 |
| `chain` | 0.926 | 0.025 | 0.914 | 0.877 | 0.900 | 0.873 |
| `identities` | 0.555 | 0.023 | 0.379 | 0.386 | 0.374 | 0.375 |
| `distinct_trees` | 2.892 | 0.236 | 25.915 | 18.941 | 13.401 | 13.276 |
| `unshared_trees` | 2.658 | 2.662 | 44.652 | 26.253 | 21.431 | 20.774 |
| `dependent_terms` | 2.816 | 0.420 | 24.101 | 13.956 | 9.931 | 10.128 |
| `alias_diamonds` | 1.126 | 0.119 | 10.922 | 8.596 | 8.516 | 12.678 |

### Goose relative to the two single-worker baselines

Ratios divide baseline median by Goose median; values above 1 mean Goose
has the lower median. They describe these implementations and workloads.

| Workload | Lean / Goose | OCaml 1 / Goose |
| --- | ---: | ---: |
| `wide` | 133.03× | 24.66× |
| `chain` | 36.82× | 36.33× |
| `identities` | 23.75× | 16.20× |
| `distinct_trees` | 12.27× | 110.01× |
| `unshared_trees` | 1.00× | 16.77× |
| `dependent_terms` | 6.70× | 57.32× |
| `alias_diamonds` | 9.46× | 91.79× |

### Observed sample ranges, milliseconds per batch

Each interval is the minimum to maximum of the seven sample averages.
These are not confidence intervals or ranges over individual batches.

| Workload | Lean native | Goose AOT | OCaml 1 | OCaml 2 | OCaml 4 | OCaml 8 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `wide` | 2.519–3.685 | 0.021–0.043 | 0.489–0.671 | 0.470–0.594 | 0.509–0.774 | 0.512–0.635 |
| `chain` | 0.824–1.829 | 0.021–0.028 | 0.797–0.977 | 0.733–0.988 | 0.885–0.925 | 0.734–0.892 |
| `identities` | 0.487–0.777 | 0.021–0.025 | 0.332–0.438 | 0.371–0.421 | 0.361–0.396 | 0.366–0.412 |
| `distinct_trees` | 2.466–3.061 | 0.229–0.248 | 21.873–27.117 | 15.869–23.670 | 10.575–14.768 | 11.567–21.975 |
| `unshared_trees` | 2.310–2.795 | 2.553–3.121 | 38.925–47.335 | 25.952–28.432 | 19.873–23.950 | 18.314–25.595 |
| `dependent_terms` | 2.595–2.939 | 0.400–0.485 | 21.976–27.713 | 12.738–15.648 | 9.637–11.767 | 9.652–11.975 |
| `alias_diamonds` | 0.992–1.176 | 0.117–0.150 | 9.357–12.136 | 7.442–10.530 | 7.597–11.223 | 12.216–18.316 |

The complete [measurement receipt](../conformance/evidence/goose-comparison/results.json),
[ordered run log](../conformance/evidence/goose-comparison/run.log), and
[differential observations](../conformance/evidence/goose-comparison/fixtures/results.json)
retain every configuration, including losses. All fixtures are beside the
differential observations. No upstream Goose marketing benchmark ratio is used.
<!-- measured-results-end -->

## Assessment and next obligation

The most useful improvements over the earlier OCaml study are the distinct-tree
and dependent-term lanes: Goose takes 0.236 ms and 0.420 ms per batch, compared
with Lean's 2.892 ms and 2.816 ms. These are lower medians by factors of 12.27 and
6.70 respectively. The large 133.03 ratio on `wide` benefits heavily from
reusing closed judgments and should not stand for ordinary Lean projects.

Fresh unshared trees remain the clearest performance target. Goose's median is
2.662 ms and Lean's is 2.658 ms, a difference of approximately 0.14 percent.
Their sample ranges overlap substantially. This experiment establishes no
useful advantage over Lean on that lane. Even there, Goose is faster than the
fastest observed OCaml bytecode median (20.774 ms at eight workers).

The next concrete performance obligation is to profile import, metadata
construction and inference on fresh unshared syntax with the same refusal
controls retained. The next compatibility obligation is broader independent
conversion/refusal coverage before extending the supported Lean fragment.
Changing caches, layout or limits should repeat the whole three-way gate;
none of these measurements authorizes theorem admission.

Hosted [source conformance run 44675673685](https://github.com/larsbx/Lean-OCaml/actions/runs/44675673685)
succeeded at implementation commit `9a6c54f961ddb6b8f6a9b0020a6265cde913fdba`,
including the existing corpus, Goose controls and smoke comparison. This hosted
smoke is separate from the full local measurements above.

## What is being compared

All engines read identical runtime TSV DAG files from the existing benchmark
generator. IDs preserve the encoded expression sharing; fresh nodes in the
unshared fixture remain distinct on input. No fixture is compiled into the
Goose executable. The seven workloads retain their existing construction:

| Workload | Purpose |
| --- | --- |
| `wide` | Distinct names sharing one large type/value pair |
| `chain` | Sequential aliases of the preceding definition |
| `identities` | Repeated identity functions |
| `distinct_trees` | Distinct normal forms with shared subtrees |
| `unshared_trees` | Separately allocated trees with distinct normal forms |
| `dependent_terms` | Dependent binders, beta applications and typed lets |
| `alias_diamonds` | Distinct base/left/right/join dependency groups |

These are synthetic controls, including workloads used during implementation.
They do not represent Mathlib, elaboration, tactics, project builds or an
untouched validation set. Full descriptions and the previous measurements are
in [the OCaml study](bytecode-optimization.md).

| Engine | Execution mode | Timed work |
| --- | --- | --- |
| Lean | Native kernel, Lean 4.34.1, native driver built with `leanc -O3` | Ordered synchronous checked insertion from `mkEmptyEnvironment 0`, explicitly using `doCheck=true` |
| OCaml | 5.5.1 bytecode, worker limits 1/2/4/8 by default | Dependency scanning/planning, syntax import, checking, worker startup/join and checked merging |
| Goose | Pinned Goose emitting standalone C, GCC `-O2`, one worker | Fresh node-arena import and metadata, duplicate lookup, validation, checking and ordered insertion |

The comparison measures implementations. Differences combine representation,
caching, work accounting, scheduling and compiler/runtime costs; they do not
isolate the programming language. In particular, Goose does not implement the
OCaml dependency-wave planner or concurrent checked-branch merge. It does not
reproduce OCaml's exact logical fuel charges: Goose cache hits charge one step,
while OCaml replays original charges and retains depth in relevant cache keys.
Same-fuel or same-depth refusal correspondence is not established.

Goose's worker model does not directly share AST references between workers.
This pilot is sequential; parallel environment transfer is a separate design
and measurement obligation. See the upstream [thread model](https://github.com/aardappel/goose/blob/9412b80f52d833c4697cffdbbf1f4eeb5195cd41/docs/reference.md).

## Bounded Goose implementation

[The checker](../reference/goose/benchmark.goose) uses a grow-only arena of
fixed-size nodes with integer child IDs. Numeric sorts, de Bruijn variables,
applications, lambdas, dependent Pis, typed lets and transparent monomorphic
constants are supported. Recursive routines implement binder-aware lifting,
capture-avoiding substitution, beta/zeta normalization, structural comparison
and dependent type inference. Pi formation is impredicative when the codomain
inhabits `Sort 0`.

Every constant occurrence is validated before reductions can erase children.
Free-variable bounds reject unclosed declarations. Both the annotation and
the value must type-check; inference of the value must agree with the declared
type through the supported conversion rules. Names enter the environment only
after success, and duplicate names cannot shadow previous bindings.

Only closed expressions have cached inferred types. Open terms are re-inferred
under their current context. Successful constant validation and normal forms
remain usable as the environment appends uniquely named checked definitions.
No failed computation installs a cached successful judgment. Every batch starts
with a fresh arena, environment, context and caches.

The checker bounds expression height and active evaluator depth at 128, arena
nodes at 2,000,000, and logical work at 10,000,000 steps per definition. The
parser separately bounds numeric fields, sort numerals, node count and
definition count. These are experiment limits, not Lean semantics. Resource
and structural failures cannot satisfy semantic refusal controls.

General universes, inductives, recursors, quotients, projections, opaque or
recursive declarations, eta, proof irrelevance, `.olean` import and general
Lean declaration admission remain outside the implemented fragment.

## Correctness gates

[The differential runner](../tools/test_goose.py) requires the exact registered
outcome for every definition in all three engines before any timing starts.
The untimed OCaml observer calls the existing public `Conversion.define` API.
The Lean observer uses checked native insertion at trust level zero and aborts
on resource or internal errors.

With 128 definitions per workload, the gate covers **964 ordered outcomes per
engine** across 16 fixtures:

- All 40 committed typing vectors, including impredicative Pis, dependent
  substitution and wrong-binder rejections at depths zero through eight.
- The historical definition sequence plus checks that failed names remain
  absent, earlier bindings survive, and a refused name can later be used by a
  valid definition: 12 ordered observations.
- Four existing optimization refusal specimens and five annotation/erasure
  controls, including ill-typed children that reduction would discard.
- Five shared-context/capture controls, including the same open application
  DAG node reused under incompatible binder contexts.
- Two registered conversion boundaries: Lean accepts declarations requiring
  eta or proof irrelevance while both bounded references return `Type_mismatch`.
- All 896 declarations in the seven 128-definition performance workloads.

The 962 remaining outcomes agree exactly after the explicit Lean-to-reference
error mapping. Goose also must reject six parser/structural/resource specimens
with the expected nonzero exit and diagnostic, without emitting a successful
observation. Finite agreement is regression evidence, not a soundness or
refinement proof.

Each timed process first runs an ill-typed-sort refusal control and a complete
warm-up. Every timed result is validated. Goose verifies the exact stored
names/types/values, clears inference and normal-form caches, re-infers values,
and structurally compares their types with the declared and saved types. This
is an internal consistency check; the independent three-way gate supplies the
cross-language observations. The existing OCaml and Lean validation routines
remain active.

## Timing and provenance

Compilation, input parsing, raw syntax construction, warm-up, post-check
validation and process startup are outside the batch timers. Goose's per-batch
arena import is timed, while arena reclamation after validation is outside;
OCaml's full major GC before each batch is outside, while GC triggered during
checking remains inside. The reported numbers are warm-process checked-batch
costs. Whole-process elapsed time is also retained in every observation but is
not interpreted as a kernel-only measurement. No memory-use claim is made.

The runner uses monotonic clocks, calibrates each configuration to a target
sample duration, shuffles configuration order deterministically and runs one
measurement process at a time. Seven samples per configuration are the default.
Median, mean, minimum, maximum and sample standard deviation are retained. The
minimum-to-maximum range describes sample averages, not a confidence interval.
The host is shared rather than an isolated performance server.

Goose is pinned to commit
[`9412b80f52d833c4697cffdbbf1f4eeb5195cd41`](https://github.com/aardappel/goose/tree/9412b80f52d833c4697cffdbbf1f4eeb5195cd41).
The runner rejects a different revision or tracked source modifications and
records compiler, generated C and executable hashes. The emitted code uses
`-O2 -DGS_DEBUG=1 --standalone`, followed by GCC `-O2`. Bounds checks remain
enabled with compiler-proven elimination; `GS_DEBUG=1` retains overflow,
narrowing-range and enum-tag checks. The runner checks that the emitted C
contains that definition. It does not use TinyCC or disable bounds checks.
These flags are documented in the pinned upstream
[command-line reference](https://github.com/aardappel/goose/blob/9412b80f52d833c4697cffdbbf1f4eeb5195cd41/docs/command_line.md).

Every sample, calibration, iteration count, fixture hash, relevant source hash,
toolchain identity and binary hash is recorded. Source changes during a run
invalidate it. Failed benchmark runs retain a failed receipt; there is no timing threshold
that can hide slow or failed configurations.

## Reproduce

Use the existing pinned OCaml/Lean acquisition recipe in
[CI](../.github/workflows/conformance.yml). Goose additionally requires Git,
CMake 3.27 or newer, a C++20 compiler and GCC. Build it outside this repository:

```sh
sh tools/build_goose.sh /absolute/path/to/new-goose-checkout
export GOOSE_SOURCE=/absolute/path/to/new-goose-checkout
export OCAMLC=/absolute/path/to/ocaml-5.5.1/bin/ocamlc
export LEAN=/absolute/path/to/lean-4.34.1/bin/lean
make test-goose
make benchmark-goose
```

`GOOSE` can override the compiler executable and `GOOSE_CC` the GCC executable;
the receipt records their paths and hashes. The source pin is always checked.
Existing benchmark targets continue to work without Goose.

The full defaults use 128 definitions, seven samples, a 150 ms target per
configuration and OCaml worker limits 1/2/4/8. A smaller smoke run is:

```sh
make benchmark-goose GOOSE_BENCHMARK_ARGS="--samples 1 --definitions 8 --workers 1 --min-sample-seconds 0.05 --output /tmp/goose-smoke"
```

CI runs the existing OCaml/Lean conformance, a Goose differential check and the
small smoke benchmark, then uploads their receipts. CI timing is a build/run
check, not a performance acceptance threshold. Local and hosted evidence must
be identified separately.
