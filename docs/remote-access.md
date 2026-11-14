# Repository identity and publication

On November 14, 2026, authenticated inspection of `larsbx/Lean-OCaml-kernel`
returned HTTP 404. Discovery found the accessible public repository
[larsbx/Lean-OCaml](https://github.com/larsbx/Lean-OCaml), repository ID
1458049913. The 404 is specific to the requested name and connection; it does
not prove that an inaccessible repository cannot exist elsewhere.

[PR #1](https://github.com/larsbx/Lean-OCaml/pull/1) merged the existing scaffold
at [802d30bc90859e82faf33049513fd82f7e507eb6](https://github.com/larsbx/Lean-OCaml/commit/802d30bc90859e82faf33049513fd82f7e507eb6).
[Conformance run 43631396215](https://github.com/larsbx/Lean-OCaml/actions/runs/43631396215)
passed at that revision. Authenticated inspection before this increment's
publication found main still at that revision. There is no access prerequisite
for the existing `Lean-OCaml` project.

The first review request explicitly limited work to a local scaffold. The
subsequent user instruction, “Open a PR against main and merge”, authorizes
publication and merge of this increment in `larsbx/Lean-OCaml`. No new remote
repository is required. Local directory names are not remote identities.

[Draft PR #2](https://github.com/larsbx/Lean-OCaml/pull/2), at
`f180db5a47e185ea3d5390bede2d76a2b80a9024`, is separate dependent-typing work.
Its [run 43631641975](https://github.com/larsbx/Lean-OCaml/actions/runs/43631641975)
and [run 43631637353](https://github.com/larsbx/Lean-OCaml/actions/runs/43631637353)
were both successful at this inspection. PR #3 initially kept
its 27 additional vectors separate. The continuation recorded below integrates
them and updates provenance and the typing count from 13 to 40.

Existing hosted results belong to their exact revisions. The committed local
receipt identifies the bytes tested here; the new pull request's hosted
workflow must pass for its actual head before merge. Repository state can
change after these dated observations.

## Dependent-typing continuation

After PR #3 merged as `cedbaa619434f6ce4ff229ae41c38339116c900f`,
PR #2 was updated against that hardened main. The integration preserves the
core, imports the original 27 added cases without changing their bytes,
updates provenance and corpus counts, and requires the intended
`Type_mismatch` for every wrong-binder case. Its current evidence is recorded
in the PR and fresh local receipt; earlier workflow successes do not validate
the new integrated head.
