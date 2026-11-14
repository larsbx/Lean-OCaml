# Lean-OCaml

Candidate reference checker for the bounded Lean β/ζ conversion fragment.
Start with [architecture](ARCHITECTURE.md).

Run with OCaml 5.5.1 and Lean 4.34.1:

```sh
sh conformance/run.sh --lean
```

Omit `--lean` to replay the checked-in vectors without regenerating them.

Run the pinned estate layout audit with `sh tools/estate-audit.sh`.

The replay includes 144 conversion comparisons and 40 closed-term typing cases
checked by Lean. `infer_closed` returns a normalized type within the β/ζ
fragment. The [typing vector schema](schemas/typing-v1.md) documents the cases.

The [definition vectors](schemas/definitions-v1.md) also exercise a persistent
reference environment for transparent monomorphic definitions.
