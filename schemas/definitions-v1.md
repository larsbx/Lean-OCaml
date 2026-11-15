# Transparent definition vectors v1

The replay starts with an empty immutable environment. Rows are processed in
order. A definition row contains five tab-separated fields: `def`, name,
declared type, value, and `true` or `false` for insertion success. Rejected rows
preserve the previous environment. An inference row contains three fields:
`infer`, expression, and expected normalized type.

Expressions follow [β/ζ vectors v1](beta-zeta-v1.md), with `cNAME` for a
monomorphic constant. Names in this corpus are simple ASCII identifiers
without spaces or tabs. The Lean generator uses checked kernel insertion
for each definition and compares inferred types by definitional equality.
OCaml requires matching results within its transparent fragment.

## Fixed ordered corpus and refusal causes

The v1 fixture has exactly seven rows in the following order. The repeated
alias name is intentional: its first occurrence succeeds and its second is a
duplicate rejection. A successful verdict or a different error cannot replace
any designated refusal.

| Row | Operation | OCaml result | Lean result |
| --- | --- | --- | --- |
| 1 | Define `ocamlRefAlias` as `Prop : Type` | Inserted | Inserted |
| 2 | Define `ocamlRefId` over that alias | Inserted | Inserted |
| 3 | Define `ocamlRefAlias` again | `Duplicate_definition` | `alreadyDeclared` |
| 4 | Define `ocamlRefMissing` using itself | `Unknown_constant` | `unknownConstant` |
| 5 | Define `ocamlRefMismatch` with `Type : Type` | `Type_mismatch` | `declTypeMismatch` |
| 6 | Define `ocamlRefNonType` with a lambda as its declared type | `Expected_sort` | `typeExpected` |
| 7 | Infer `ocamlRefId` | `Prop → Prop` | Definitionally equal to `Prop → Prop` |

These mappings describe the four particular fixtures, not a universal mapping
of every error or precedence rule between implementations. Exact row order,
names, expressions and success/refusal flags are validated. Missing, repeated,
reordered or altered rows fail the replay. Work, height, integer, scope and
internal failures cannot satisfy an expected semantic rejection.

The imported `Generate.lean` remains byte-identical and retains generic
exception handling for its negative rows. The additional
`oracles/ValidateDefinitionRefusals.lean`, run by `conformance/run.sh --lean`,
supplies the precise Lean checks above using normal checked kernel insertion.
Its resource/internal exception controls inject values into the classifier;
they do not deliberately exhaust memory or time.

Both replays check that prior successful bindings remain available after a
refusal, that refused fresh names are absent, and that earlier environment
snapshots remain unchanged. Lean starts with trusted `Init`; the OCaml reference
starts empty. The correspondence concerns these fresh named monomorphic
definitions only. It does not equate the complete environments, implement
general declaration admission, or grant the reference acceptance authority.
