# Language boundaries

| Language | Path | Role |
|---|---|---|
| OCaml | `reference/`, `conformance/*.ml` | Owns the reference observations and local replay |
| Lean | `oracles/Generate.lean`, `oracles/RustBaseline.lean` | Generates the comparison evidence through the trusted kernel |
| Shell | `conformance/run.sh`, CI | Builds and replays the two paths |
| Python | `tools/check_provenance.py`, `tools/acceptance.py` | Checks provenance and records unsigned execution evidence |

The OCaml reference has no runtime dependency on Lean, the oracle generator,
or a fixture parser. The conformance executable links the reference and reads
the versioned TSV contract. Generated TSV is derived from the Lean generator
using the repository's pinned Lean toolchain and is regenerated in CI.

The Rust baseline registers exactly two intentional disagreements; all other
disagreements fail. The source manifest records copied generators and fixtures
with exact upstream paths, revisions and byte identities. The generated OCaml
property corpus has no trusted Lean typing or conversion evidence.
