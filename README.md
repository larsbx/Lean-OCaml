# Lean-OCaml: bounded conversion reference

Candidate OCaml reference for scoped Lean expression syntax, capture-avoiding
substitution, and bounded β/ζ conversion. The existing separate closed-term
typing reference and transparent monomorphic-definition environment remain
available. This project does not admit Lean declarations or certify theorems.

## Build and check

Use OCaml **5.5.1**, Python **3.11+**, Git, POSIX shell and `diff`. Trusted
oracle regeneration additionally requires Lean **4.34.1**, upstream commit
`5045d0056413266e57c625dcd7c365b10e377c52`. The OCaml code links only the
standard library; no Dune, Opam package or native compiler is required.

```sh
make test                 # Compile and replay all OCaml tests and source hashes
make test-lean            # Also regenerate Lean fixtures and strictly replay refusals
make audit                # Fetch and verify the pinned external estate auditor
make acceptance           # Write exact-source local logs and an unsigned receipt
```

The build runs in a temporary directory and removes it after execution. It
checks compiler identity before compiling and checks Lean version and commit
before regeneration. For toolchains outside PATH, supply absolute paths:

```sh
export OCAMLC=/absolute/path/to/ocamlc
export LEAN=/absolute/path/to/lean
make test-lean
```

For offline governance checks, supply the already obtained external auditor:

```sh
make acceptance ESTATE_AUDITOR=/absolute/path/to/audit_estate_layout.py
```

The wrapper verifies its digest against `ESTATE.toml`. The pinned compiler
acquisition/build recipe is in `.github/workflows/conformance.yml`; target
versions are recorded in `.ocaml-version` and `lean-toolchain`. Missing tools,
wrong versions, failed generation and changed fixture bytes fail the command.

## Review surfaces

| File | Purpose |
| --- | --- |
| [Module interface](reference/conversion.mli) | Public operations and refusal categories |
| [Implementation](reference/conversion.ml) | Scope, substitution, checked heights and metered conversion |
| [Correspondence contract](docs/kernel-correspondence.md) | Lean mapping, disagreements and unsupported features |
| [Source provenance](conformance/provenance.json) | Upstream revisions, paths, Git blob identities and SHA-256 hashes |
| [Definition contract](schemas/definitions-v2.md) | Ordered reference-environment observations and exact rejection causes |
| [Validation guide](docs/validation.md) | Test inventory and interpretation of exact-source evidence |
| [Architecture](ARCHITECTURE.md) | Estate authority and language boundaries |
| [Repository identity](docs/remote-access.md) | Accessible project name and publication history |

The extended corpus has 144 conversion, 40 typing and 7 environment vectors.
The dependent-typing cases cover zero to eight intervening binders, with exact
wrong-binder type-mismatch rejections in both OCaml and the supplementary Lean
replay. The definition corpus separately checks exact rejection causes and
preservation of prior environment snapshots after failed insertions. The
imported Rust baseline adds 19 rows, including two designated
Lean-true / βζ-false cases for function η and proof irrelevance. The local suite also runs
1,024 deterministic generated cases and adversarial boundary controls; those
properties are internal checks, not Lean-checked theorems.

The committed [local receipt](conformance/evidence/acceptance.json), source
manifest and logs identify the exact bytes tested. Hosted CI is separate
revision-specific evidence visible on the pull request or commit. Neither
finite test agreement nor a passing estate audit establishes full Lean kernel
compatibility or changes `acceptance_authority = false`.
