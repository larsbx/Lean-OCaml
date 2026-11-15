# Bounded OCaml conversion correspondence

## Scope and authority

The OCaml reference observes scoped syntax, capture-avoiding substitution and
bounded β/ζ conversion. It has no declaration or theorem admission authority.
`ESTATE.toml` retains `acceptance_authority = false` and the implementation stays
in `reference/`. Existing closed-term inference and transparent monomorphic
reference definitions are separate APIs, not general Lean kernel admission.

The integrated baseline is [Lean-OCaml main 08340ce24bcdbb6c8563152a7ea640406d67887b](https://github.com/larsbx/Lean-OCaml/tree/08340ce24bcdbb6c8563152a7ea640406d67887b).
The cross-language contract is [lean-rust 27ececb284b82b7d43884af317c7fcb89feb3da0](https://github.com/larsbx/lean-rust/blob/27ececb284b82b7d43884af317c7fcb89feb3da0/docs/kernel-correspondence.md).
Trusted oracle execution pins [Lean 4.34.1 commit 5045d0056413266e57c625dcd7c365b10e377c52](https://github.com/leanprover/lean4/tree/5045d0056413266e57c625dcd7c365b10e377c52).
The reproducible OCaml compiler target is **5.5.1**.

## Representation and binding

| OCaml | Lean encoding | Scope |
| --- | --- | --- |
| `Var i` | `Expr.bvar i` | Zero is innermost; nonnegative index must be available. |
| `Sort n` | `Expr.sort` with n successors of level zero | Nonnegative machine integer; no general level expression. |
| `App (f, a)` | `Expr.app` | Both children use current scope. |
| `Lam (a, b)` | `Expr.lam` | Domain at current scope; body under one binder. |
| `Pi (a, b)` | `Expr.forallE` | Domain at current scope; body under one binder. |
| `Let (a, v, b)` | `Expr.letE` | Type and value at current scope; body under one binder. |
| `Const name` | No bare-conversion encoding | Refused by bare conversion with `Unknown_constant`. |

Binder names and binder-info metadata are absent; domains remain part of
normalization and structural comparison. Ambient scope counts available outer
bound variables, without supplying their types. Every input child is validated
before reduction, including discarded arguments, annotations and unused let
values. Well-scoped syntax need not be well typed or normalizing.

## Operations

The exact signatures are in [conversion.mli](../reference/conversion.mli).

| Operation | Contract |
| --- | --- |
| `validate_scope ~fuel ~scope term` | Check complete syntax, scope, numeric sorts, height and budget. |
| `instantiate ~fuel ~scope ~body replacement` | Body scoped in scope+1, replacement in scope; remove one binder without capture. |
| `whnf_in ~fuel ~scope term` | Head β/ζ reduction along function positions; stop under unapplied lambdas/Pis and leave neutral arguments unreduced. |
| `normalize ~fuel ~scope term` | Full β/ζ normalization, including domains, bodies and neutral arguments. |
| `beta_zeta_equal_in ~fuel ~scope left right` | Validate both inputs, normalize, then compare structures under one shared budget. |
| `whnf ~fuel term` | Closed wrapper using scope zero. |
| `beta_zeta_equal ~fuel left right` | Closed wrapper using scope zero. |

At substitution depth d, indices below d are preserved, index d is replaced
by the argument lifted through d binders, and larger indices are decremented.
Lifting preserves binders internal to the replacement. This follows the
binding convention of Lean's `Expr.instantiate1` in the pinned oracle.

β substitutes an argument into an applied lambda body; ζ substitutes a let
value into its body. No pointer-identity shortcut bypasses normalization. An
identical divergent term may exhaust the OCaml budget even when the Rust
baseline's post-validation pointer reflexivity shortcut succeeds. This is an
explicit operational difference for untyped divergent syntax.

## Outcomes and resource limits

Private immutable terms carry checked heights. Inputs, constructed intermediate
terms and output syntax have height at most 128, with leaves at height one.
Active evaluator-context depth is also bounded. Traversal, substitution,
normalization, comparison and result export share an operation budget.
Work units are not comparable with Rust fuel or a count of β/ζ contractions.

| Outcome | Meaning |
| --- | --- |
| `Ok true` | Validated operands produced structurally equal β/ζ normal forms; no well-typedness claim. |
| `Ok false` | Completed normal forms differ within this fragment; Lean may equate them through additional rules. |
| `Invalid_scope` | Negative scope/index or an unavailable bound-variable index. |
| `Invalid_universe` | Negative numeric sort. |
| `Limit_exceeded` | Exhausted work, nonpositive fuel, or defensive runtime stack-overflow refusal; inconclusive about equality and divergence. |
| `Height_limit` | Excessive syntax height or active evaluator-context depth. |
| `Index_overflow` | Checked index/scope/successor arithmetic cannot be represented safely. |
| `Unknown_constant` | Constant supplied to bare conversion, or absent from the separate reference environment. |

Error precedence is not a contract for inputs violating several restrictions.
No error can satisfy an expected false conversion row. Only the designated
semantic OCaml errors can satisfy typing-refusal rows; resource and structural
failures cannot. Cyclic public OCaml values receive height/work refusals. These
limits do not claim general hostile-process isolation or whole-process memory
bounds, and `Limit_exceeded` does not prove nontermination.

## Direction of correspondence

For well-typed encoded inputs, successful β/ζ conversion is expected to imply
trusted Lean conversion. This is a design obligation supported by finite
checks, not a general OCaml-to-Lean refinement theorem. The reverse implication
fails for the intentionally smaller rule set.

| Registered case | Lean | β/ζ reference | Missing rule |
| --- | --- | --- | --- |
| `eta-outside-fragment` | true | false | Function η |
| `proof-irrelevance-outside-fragment` | true | false | Proof irrelevance |

The harness checks these exact identities and verdict pairs. They do not
permit arbitrary disagreement: altered verdicts, errors, duplicate/missing
rows and unregistered cases fail. A successful suite checks this contract;
it does not claim full agreement with Lean.

Unsupported features include general universe parameters/max/imax, opaque
constants and general δ, inductives/ι, recursors, projections, free variables,
metavariables, quotients, η, proof irrelevance, `.olean` import and declaration
or theorem admission. The existing transparent monomorphic reference
subsystem does not fill those gaps.

## Provenance and evidence

[provenance.json](../conformance/provenance.json) records five byte-identical
imports and two derived artifacts, their original paths, immutable revisions,
Git blob IDs and SHA-256 hashes. `conformance/rust-v1.tsv` copies `oracle/cases.tsv` from Rust
27ececb; `oracles/RustBaseline.lean` copies its `oracle/Kernel.lean` under the
user's explicit reuse instruction. This is attributed oracle source, not an
imported runtime kernel. The canonical estate auditor remains external.

The baseline oracle uses trusted `Kernel.check`, `Kernel.whnf` and
`Kernel.isDefEq` on closed typed cases, and `Expr.instantiate1` on open syntax.
Its 19 rows contain nine matching equalities, two designated disagreements,
four WHNF results and four substitutions. The extended 191-row corpus
(144 conversion, 40 typing, 7 environment) has a separate generator derived
from PR #2 at f180db5a47e185ea3d5390bede2d76a2b80a9024. Both are regenerated
with pinned Lean and compared byte for byte. A supplementary strict Lean
replay checks all 40 typing rows and requires the designated semantic errors
for all 14 refusals. The generator checks the seven ordered environment rows
and records the designated kernel exception for each of the four definition
refusals. The 1,024 generated OCaml cases are
internal properties and receive no Lean checking. See
[validation.md](validation.md) for the execution record.

Any extension must specify its expression/environment mapping, add trusted
positive and rejection cases, record directional disagreements and review
any change in acceptance authority.

The dependent-typing extension uses 18 positive β/ζ examples and nine
wrong-binder rejections over depths zero through eight. Each wrong-binder
row must produce OCaml `Type_mismatch` and Lean `appTypeMismatch`; other
semantic errors and every resource refusal fail that observation. See
[ADR 0003](0003-dependent-typing-integration.md).

The reference-definition extension distinguishes duplicate names, unavailable
self-references, declared-type mismatches and invalid type annotations. The
OCaml and Lean replays check persistence of prior environment snapshots after
refusal. Those exact fixture mappings and their limited environment scope are
specified in [definitions v2](../schemas/definitions-v2.md) and
[ADR 0004](0004-definition-refusal-evidence.md). Lean's checked oracle insertion
does not introduce OCaml declaration or theorem admission.
