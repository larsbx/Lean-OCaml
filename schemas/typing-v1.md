# Closed-term typing vectors v1

Each row contains four tab-separated fields: the tag `type`, a unique case
identifier, a closed expression, and its expected β/ζ-normalized type or the
literal `refused`. Expression encoding follows [β/ζ vectors v1](beta-zeta-v1.md).

Lean's kernel checks the term and compares each expected type to the inferred
type by definitional equality. For refusal rows Lean must reject the term.
OCaml replay requires a matching normalized type or a typing error. Scope,
numeric overflow, and work-budget errors cannot satisfy typing-refusal rows.

The generated cases place zero to eight intervening binders between the
argument and its use. At each depth they check a β application, the same
application wrapped in a let, and a rejection where the argument has the
other bound type.

For the nine named `depth-0-wrong-binder` through
`depth-8-wrong-binder` rows, OCaml must return exactly `Type_mismatch`.
`Expected_sort`, `Expected_function`, or any scope/universe/resource refusal
cannot count as that intended rejection. All nine IDs must be present.
The replay's injected-error controls exercise this distinction separately.

The imported generator retains generic exception handling for refusal rows.
`oracles/ValidateTypingRefusals.lean`, invoked by `conformance/run.sh --lean`,
adds strict checking of all 40 typing rows. It requires `funExpected` for
`nonfunction`, `appTypeMismatch` for `argument-mismatch` and the nine
wrong-binder cases, `letTypeMismatch` for `let-mismatch`, and `typeExpected`
for `binder-not-type` and `pi-body-not-type`. Any other kernel exception,
including resource or internal errors, fails. The 26 positive expected types
are checked independently and compared to inferred types by Lean definitional
equality. The fixed inventory, duplicate IDs and expected-result forms are
validated before a successful result can be reported.
