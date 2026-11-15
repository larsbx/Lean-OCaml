# Language boundaries

| Language | Path | Role |
|---|---|---|
| OCaml | `reference/`, `conformance/*.ml` | Owns the reference observations and local replay |
| Lean | `oracles/Generate.lean`, `oracles/RustBaseline.lean`, `oracles/ValidateTypingRefusals.lean` | Generates comparison evidence and checks exact semantic refusals through the trusted kernel |
| Shell | `conformance/run.sh`, CI | Builds and replays the two paths |
| Python | `tools/check_provenance.py`, `tools/acceptance.py` | Checks provenance and records unsigned execution evidence |

The OCaml reference has no runtime dependency on Lean, the oracle generator,
or a fixture parser. The conformance executable links the reference and reads
the versioned TSV contract. Generated TSV is derived from the Lean generator
using the repository's pinned Lean toolchain and is regenerated in CI.

The generator checks exact definition refusals during regeneration. The
supplementary typing checker validates the imported typing fixture. Definition
controls include a forced Lean kernel recursion refusal and injected resource
and internal exceptions. Lean declaration insertion is confined to the oracle
process.

The Rust baseline registers exactly two intentional disagreements; all other
disagreements fail. The source manifest records imports and derived artifacts
with exact upstream paths, revisions and byte identities. The generated OCaml
property corpus has no trusted Lean typing or conversion evidence.
