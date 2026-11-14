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
