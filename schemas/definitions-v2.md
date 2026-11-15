# Transparent definition vectors v2

`conformance/generated.tsv.defs` contains six ordered definition rows and
one final inference row. Each definition row has five tab-separated fields:
`def`, name, declared type, value, and the checked Lean insertion outcome.
The final row contains `infer`, expression, and expected normalized type.
Expressions use [β/ζ vectors v1](beta-zeta-v1.md), extended with `cNAME` for
simple monomorphic constant names.

| Fixture | Lean outcome | OCaml replay result |
| --- | --- | --- |
| `ocamlRefAlias` and `ocamlRefId` | `accepted` | `Ok` with the next environment |
| Second `ocamlRefAlias` | `alreadyDeclared` | `Duplicate_definition` |
| `ocamlRefMissing` | `unknownConstant` | `Unknown_constant` |
| `ocamlRefMismatch` | `declTypeMismatch` | `Type_mismatch` |
| `ocamlRefNonType` | `typeExpected` | `Expected_sort` |

Lean imports `Init` and calls `Environment.addDeclCore` with kernel checking
enabled. OCaml starts with an empty reference environment. Each engine applies
successful insertions in order and retains the previous environment after a
refusal. Both paths check preservation of accepted bindings and absence of
fresh refused names. The final row checks the identity's inferred type.

The generator requires the designated `Lean.Kernel.Exception` constructor
for each negative declaration. OCaml requires the mapped error for the
ordered fixture name and tag. Resource limits, other semantic failures,
internal exceptions, and the legacy Boolean tags fail the relevant checks.
These rows cover safe, transparent monomorphic definitions in the reference
fragment. See [validation](../docs/validation.md) for execution evidence.
