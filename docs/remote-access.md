# Repository identity and publication evidence

The canonical repository is **[larsbx/Lean-OCaml](https://github.com/larsbx/Lean-OCaml)**,
GitHub repository ID 1458049913. Use `Lean-OCaml` for this project in source,
documentation, review requests and future implementation work.

## Implemented baseline

| Increment | Pull request | Merge revision |
| --- | --- | --- |
| Initial reference scaffold | [PR #1](https://github.com/larsbx/Lean-OCaml/pull/1) | [802d30bc](https://github.com/larsbx/Lean-OCaml/commit/802d30bc90859e82faf33049513fd82f7e507eb6) |
| Scoped conversion and resource hardening | [PR #3](https://github.com/larsbx/Lean-OCaml/pull/3) | [cedbaa619](https://github.com/larsbx/Lean-OCaml/commit/cedbaa619434f6ce4ff229ae41c38339116c900f) |
| Dependent typing and precise typing refusals | [PR #2](https://github.com/larsbx/Lean-OCaml/pull/2) | [08340ce2](https://github.com/larsbx/Lean-OCaml/commit/08340ce24bcdbb6c8563152a7ea640406d67887b) |

The definition-refusal increment starts from main
`08340ce24bcdbb6c8563152a7ea640406d67887b`. Authenticated inspection on
November 14, 2026 (America/New_York) verified that its
[post-merge conformance run 43646432632](https://github.com/larsbx/Lean-OCaml/actions/runs/43646432632)
completed successfully. The estate audit, pinned compiler build, pinned Lean
installation, OCaml replay and Lean regeneration steps all passed.

PR #2's hosted jobs were queued when it merged; its merge record states that
fact. The later successful run is separate hosted evidence at the merge
revision. It does not automatically establish a pass for subsequent changes.

## Evidence and publication

The user's PR-and-merge instruction authorizes continued publication in this
repository. Each increment records its actual local acceptance, source digest,
hosted workflow status and merge revision. A pending hosted run is not a pass.
The local receipt and source manifest bind the tested bytes; hosted results
belong to their exact revisions. Repository state can change after any dated
observation. Follow applicable repository rules and record the evidence used
for the particular merge rather than treating a historical PR's status as a
current result.

The current implementation remains a non-authoritative reference with
`acceptance_authority = false`. Neither publication nor a passing audit changes
the kernel admission boundary.
