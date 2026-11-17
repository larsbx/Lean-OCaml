# Authority and architecture

This candidate is an independent implementation of bounded β/ζ conversion.
The OCaml reference reports equality, an inferred type, or a refusal. Lean
checks the comparison operands and typing cases when generating the vectors.
CI fails on any unregistered disagreement or replay error. The Rust baseline
explicitly checks two designated disagreements for unsupported η and proof
irrelevance; these are not claimed as full Lean conversion agreement.
The project owns no declaration, theorem, or deployment acceptance boundary.

The v1 fragment has de Bruijn indices, numeric universe sorts, application,
lambda, dependent function syntax, and let. The reference checks scope and
bounds traversal and reduction by a shared work budget. The typing reference checks
closed terms in the same syntax, with numeric universe successor and impredicative
Pi formation. It uses lifted types for bound-variable lookup, substitutes
arguments into dependent codomains, and expands checked let bindings before
inferring the body. Compatibility is evidenced on the checked corpus.
An immutable reference environment supports transparent monomorphic definitions.
Insertion expands references against the prior snapshot, checks the closed
annotation and body, and stores the expanded value. Inference expands constants
under the same work budget used for type inference. This models transparent
unfolding within the fragment. Names are case-sensitive strings.

The reference batch API derives dependencies from all constant occurrences and
checks ready definitions concurrently against one immutable snapshot per wave.
Its worker count and job inventory are bounded. A private checked-branch merge
accepts exactly one addition over the identical parent snapshot and distinct
names. This relies on stored values being closed and fully expanded. Any failed
wave returns no environment and prevents later waves from running. One-worker
execution uses the same waves and budgets as parallel execution; it is the
sequential reference for this new contract. See the
[batch schema](schemas/definition-batch-v1.md) and
[concurrency guide](docs/reference-concurrency.md).

The ordered definition corpus requires the designated semantic refusal for each
failed insertion in both OCaml and the trusted Lean checker. Resource/internal
errors cannot satisfy those observations. The replay also checks that prior
snapshots remain usable and refused fresh names are absent. These are bounded
reference-environment observations, not general declaration admission.

General universe expressions, opaque constants, η, proof irrelevance, inductives,
recursors, and declaration admission require future correspondence work.

The scoped-conversion core enforces height 128 on inputs, intermediate trees
and outputs. Traversal, normalization, structural comparison and export share
an operation budget. Height and arithmetic refusals remain distinct. See the
[correspondence contract](docs/kernel-correspondence.md) for full boundaries.

The kernel plane records the unimplemented admission boundary. See
[language boundaries](LANGUAGE_BOUNDARIES.md) and the [vector schema](schemas/beta-zeta-v1.md).
