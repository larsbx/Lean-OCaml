# ADR 0003: Integrate dependent typing with the hardened conversion reference

Status: implemented for review. The reference remains non-authoritative;
no declaration or theorem admission boundary changes.

## Problem and decision

PR #2 was based on the original OCaml reference at main 802d30bc. PR #3 then
merged the scoped, height-checked conversion core as main cedbaa619. Combining
them requires preserving the hardened API and refusal behavior, resolving the
README conflict, updating source provenance and replacing the old acceptance
receipt with a fresh run for the integrated tree.

Use the exact generator and type fixture bytes from PR #2 revision
`f180db5a47e185ea3d5390bede2d76a2b80a9024`, integrated with main
`cedbaa619434f6ce4ff229ae41c38339116c900f`. Keep the conversion core unchanged.
The extended corpus has 144 conversion, 40 typing and 7 environment rows;
the separate Rust baseline adds 19 rows, for 210 trusted-oracle observations.
Two Rust baseline rows retain their deliberate directional disagreements.

## What the new cases establish when checked

For each depth from zero through eight, independently bound types A and B
surround an argument x and the intervening binders. A direct β example applies
an identity expecting A to x:A. A ζ example wraps that application in a let.
The negative case binds x:B while preserving the function domain A.

There are 18 positive and nine negative cases. The OCaml negative result must
be exactly `Type_mismatch`: `Expected_sort` or `Expected_function` would be a
different regression because both type variables and the function shape are
valid. Scope, universe, arithmetic, height and work-limit errors likewise
cannot satisfy a wrong-binder fixture. The earlier 13 type cases retain their
specified semantic-refusal handling.

These cases exercise lifted context lookup, the distinction between bound
types, and codomain binder-index adjustment/removal across binder depths.
The identity codomain refers to the outer type A but does not depend on the
argument x itself; these cases do not establish general dependent-codomain
argument substitution.
They provide finite differential evidence, not a general type-soundness or
program-refinement theorem. The expected types and rejections are checked by
pinned Lean execution; generated OCaml property tests remain a separate,
untyped internal evidence lane.

The imported generator accepts any kernel exception on a negative typing row.
The new supplementary `oracles/ValidateTypingRefusals.lean` therefore replays
the exact 40-row inventory independently: 26 positive types and 14 designated
semantic refusals, including exactly `appTypeMismatch` for all nine wrong-binder
cases. Five injected classifier controls reject timeout, memory, recursion,
interruption and internal exceptions. Seven OCaml controls separately verify
that the stricter wrong-binder verdict cannot be replaced by another outcome.
The four inherited negative definition rows retain the generator's generic
exception handling and are not presented as precise semantic-refusal evidence.

## Acceptance and provenance

The generator and type corpus are copied byte for byte from the original PR
revision. Their original source revision and content digests are recorded
separately from the older unchanged oracle artifacts. `integration_parents`
records both public source parents, while the receipt's source digest binds
the complete resulting source tree.

Fresh local acceptance compiles OCaml 5.5.1, replays all inherited and added
checks, regenerates all four fixture files under Lean 4.34.1, executes the
strict typing replay, and runs the pinned external estate auditor. Three Python
regression checks ensure Git worktree metadata is excluded from receipts and
source symlinks remain refused. The new head's hosted workflow provides
separate execution evidence. Old PR #2 and PR #3 workflow runs are historical
and must not be attributed to the integrated source.

Future general universe, inductive, quotient, admission, η and proof-irrelevance
work remains outside this increment. No full Lean kernel compatibility or
estate acceptance authority is claimed.
