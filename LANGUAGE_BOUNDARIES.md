# Language boundaries

| Language | Path | Role |
|---|---|---|
| OCaml | `reference/`, `conformance/*.ml` | Owns the reference observations and local replay |
| Lean | `oracles/Generate.lean`, `oracles/RustBaseline.lean`, `oracles/Validate*Refusals.lean` | Generates comparison evidence and independently checks exact semantic refusals through the trusted kernel |
| Shell | `conformance/run.sh`, CI | Builds and replays the two paths |
| Python | `tools/check_provenance.py`, `tools/acceptance.py` | Checks provenance and records unsigned execution evidence |

The OCaml reference has no runtime dependency on Lean, the oracle generator,
or a fixture parser. The conformance executable links the reference and reads
the versioned TSV contract. Generated TSV is derived from the Lean generator
using the repository's pinned Lean toolchain and is regenerated in CI.

Bounded concurrency stays in the OCaml reference plane. Workers call the existing
definition checker; only already checked, closed sibling values can be merged.
No worker verdict, successful batch or benchmark grants theorem-admission
authority. Generated dependency-graph controls are internal OCaml evidence;
the existing Lean fixtures are retained and regenerated separately. The bundled
Unix library is used only by tests and benchmark timing, not reference checking.

The supplementary typing and definition checkers replay the unchanged imported
fixtures with exact semantic-error requirements. Their resource/internal
exception controls are injected classifier tests, not attempts to exhaust
the host. Lean definition insertion occurs only inside the oracle process;
it does not grant declaration-admission authority to the OCaml reference.

The Rust baseline registers exactly two intentional disagreements; all other
disagreements fail. The source manifest records copied generators and fixtures
with exact upstream paths, revisions and byte identities. The generated OCaml
property corpus has no trusted Lean typing or conversion evidence.
