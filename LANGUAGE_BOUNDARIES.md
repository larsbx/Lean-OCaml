# Language boundaries

| Language | Path | Role |
|---|---|---|
| OCaml | `reference/`, `conformance/replay.ml` | Owns the reference observations and local replay |
| Lean | `oracles/Generate.lean` | Generates the comparison evidence through the trusted kernel |
| Shell | `conformance/run.sh`, CI | Builds and replays the two paths |

The OCaml reference has no runtime dependency on Lean, the oracle generator,
or a fixture parser. The conformance executable links the reference and reads
the versioned TSV contract. Generated TSV is derived from the Lean generator
using the repository's pinned Lean toolchain and is regenerated in CI.
