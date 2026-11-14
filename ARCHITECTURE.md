# Authority and architecture

This candidate is an independent implementation of bounded β/ζ conversion.
The OCaml reference reports equality, an inferred type, or a refusal. Lean
checks the comparison operands and typing cases when generating the vectors.
CI fails on any divergence or replay error.
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

General universe expressions, opaque constants, η, proof irrelevance, inductives,
recursors, and declaration admission require future correspondence work.

The kernel plane records the unimplemented admission boundary. See
[language boundaries](LANGUAGE_BOUNDARIES.md) and the [vector schema](schemas/beta-zeta-v1.md).
