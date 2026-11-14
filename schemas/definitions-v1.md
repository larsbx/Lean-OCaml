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
