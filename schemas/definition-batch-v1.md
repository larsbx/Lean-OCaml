# Reference definition batches v1

Status: implemented candidate reference. This contract describes an OCaml API,
not a serialized Lean declaration format or theorem-admission mechanism.

## Inputs and limits

`Definition_batch.run` takes an immutable `Conversion.environment`, a list of
definitions, a worker count, a dependency-scan budget and a merge budget. Each
definition contains a name, declared type, value and its own checking budget.
Names are nonempty, case-sensitive strings and must be unique within the batch.
The input list and expressions must remain immutable during execution.

There are at most 4,096 definitions and 1–64 workers. The calling domain is one
worker; a wave starts at most `min(workers, wave_size) - 1` additional domains.
Each group is joined before the next wave starts. Domains are not retained
between waves. A one-job wave creates no additional domain.

The definition-list traversal is bounded before converting it to an array, so
a cyclic list cannot hang planning. Each expression scan visits both the type
and value under one `scan_fuel` budget and enforces the existing height limit
of 128. It visits every child, including annotations and subexpressions that
reduction would erase. Scanning collects actual `Const` occurrences; callers
cannot supply a dependency list that omits a reference.

## Dependency waves and the sequential reference

A reference to another name in this batch is a prerequisite. A reference to a
name outside the batch is resolved by the existing checker against the supplied
environment; absence is the exact `Unknown_constant` checking refusal.
A batch definition that collides with an existing name fails with
`Duplicate_definition`; dependent jobs cannot fall back to that old binding.

The planner computes the full topological schedule before any checking. Each
wave consists of every currently ready definition, in original input order.
Indegrees and reverse successor lists process each dependency edge once; the
next frontier is sorted by input index. Self-cycles and larger cycles are
refused. The cycle report includes every remaining definition blocked by a
cycle, including its downstream dependents.

Acyclic forward references are permitted. The batch is therefore a separate
contract from the ordered seven-row `definitions-v1` corpus. That corpus and
the existing `Conversion.define` operation retain their semantics.

Every job in a wave checks against the same immutable snapshot. After all jobs
finish, successful branches are merged in input order, and the next wave uses
that result. Each job has a private checking budget. Each wave has a fresh
`merge_fuel` budget, independent of the number of workers.

`workers = 1` uses this identical plan, snapshots and merge order. This is the
sequential reference for comparing success and exact refusal results. An
arbitrary fold of `Conversion.define` over successively extended environments
has different lookup costs and need not have the same low-fuel behavior.

## Checked sibling merge

The environment representation remains private. `merge_checked_branches`
accepts only branches with exactly one checked binding over the physically
identical base snapshot. It rejects unchanged environments, different parents,
multiple additions and duplicate sibling names. It exports no unchecked term
or environment constructor.

This merge relies on a specific property of the current reference: `define`
fully expands references and checks closed values before storing them. Its
private stored terms contain no constant nodes. Merging checked sibling values
therefore cannot resolve a name differently. This argument must be revisited
before adding opaque constants, recursive definitions or unexpanded references.

Insertion order is the input order: the last branch becomes the first lookup
entry. The merge charges one unit at entry, one per inspected branch and one
per inserted binding. Insufficient budget is `Merge_limit_exceeded`; an empty
merge with positive fuel returns the base. No input snapshot is mutated.

## Outcomes

Success returns the resulting reference environment and the exact name waves.
Any failure returns no environment. Even successful earlier waves remain
unpublished to the caller when a later wave fails; the supplied base remains
unchanged.

| Outcome | Meaning |
| --- | --- |
| `Invalid_workers`, `Too_many_definitions` | Configuration exceeds the API bounds. |
| `Invalid_name`, `Duplicate_name` | The batch cannot name its jobs unambiguously. |
| `Dependency_scan_failed` | Dependency discovery exceeded its height/work bound. |
| `Dependency_cycle` | No valid topological completion exists for the reported residual. |
| `Check_failed` | All exact `Conversion.error` results from the first failed wave, in input order. |
| `Worker_failed` | Unexpected callback, domain-start/join or scheduler failure. |
| `Merge_failed` | Checked branches failed the merge boundary or its resource budget. |

All started domains are joined before a normal return or a handled runtime
failure. Unexpected callback exceptions are reported by lowest job index,
after all callbacks in the wave have finished. Resource and execution failures
never count as a successful definition or a designated semantic refusal.
Planning/merge allocation exceptions may propagate without a structured result;
the API provides neither process isolation nor recovery from process termination.

No cancellation API, persistent worker pool, parallel reduction, imported
`.olean` environment or general Lean declaration admission is introduced.
