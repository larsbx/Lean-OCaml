# ADR 0001. Independent OCaml conversion reference

Status: proposed with the initial scaffold.

Use OCaml variant types and structural comparison to make binding and reduction
rules easy to inspect independently of the Rust implementation. Pin the OCaml
and Lean toolchains and keep the executable dependency-free. Start with the
144 generated typed comparisons from the lean-rust binder-depth suite. The
local generator reproduces those records byte for byte. Scope errors and work
limits have distinct results. Any future declaration admission requires a
separate authority decision and evidence for the type checker.

The comparison source is the generated subset of
`larsbx/lean-rust` candidate revision `3ba8f68579b6ea4c0bcec2d8b3d349adfafcde11`
(`oracle/cases.tsv`). The OCaml scaffold's executable and generator are
self-contained. The two implementations require no runtime code from one another.
