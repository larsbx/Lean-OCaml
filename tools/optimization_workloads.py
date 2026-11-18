#!/usr/bin/env python3
"""Supplemental matched-input workloads for the bytecode optimization study.

These families exercise distinct normal forms, unshared input trees, dependent
binders, beta/zeta reduction, and nonidentical dependency diamonds. They were
also used during optimization; they are supplemental controls, not an untouched
out-of-sample validation set. The caller supplies the existing benchmark DAG
factory so both tools use the same serialization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Callable


WORKLOADS = (
    "distinct_trees",
    "unshared_trees",
    "dependent_terms",
    "alias_diamonds",
)

DESCRIPTIONS = {
    "distinct_trees": (
        "Independent closed type definitions with pairwise distinct normal forms; "
        "each contains a six-level shared binary type tree and a bit-encoded "
        "asymmetric type motif. No complete type/value pair repeats."
    ),
    "unshared_trees": (
        "Independent closed type definitions with pairwise distinct normal forms; "
        "each contains a four-level binary tree whose children and literals are "
        "constructed separately. No expression node is shared across definitions."
    ),
    "dependent_terms": (
        "Closed polymorphic projections under one to twenty-four value binders, "
        "with alternating beta applications and typed lets. Values and annotations "
        "depend on de Bruijn indices at different scopes."
    ),
    "alias_diamonds": (
        "Groups of four definitions: a distinct closed type, two aliases of it, "
        "and an arrow using both aliases. All annotations are closed and free of "
        "constants; each diamond spans three checking waves."
    ),
}

DagFactory = Callable[[], Any]


def _require_count(count: int) -> None:
    if not isinstance(count, int) or not 1 <= count <= 512:
        raise ValueError("definition count must be in 1..512")


def _tree(graph: Any, depth: int, leaf: int) -> int:
    """Binary type tree with explicitly shared children at each level."""
    for _ in range(depth):
        leaf = graph.node("p", leaf, leaf)
    return leaf


def _motif(graph: Any, index: int, width: int, leaf: int) -> int:
    # The initial asymmetric motif differs from its leaf. Fixed-length left/right
    # wrapping therefore encodes the index injectively in the beta-normal form.
    value = graph.node("p", leaf, graph.node("p", leaf, leaf))
    for shift in range(width):
        value = graph.node("p", value, leaf) if (index >> shift) & 1 \
            else graph.node("p", leaf, value)
    return value


def _fresh_motif(graph: Any, index: int, width: int) -> int:
    """Same type motif, but every literal occurrence gets a fresh DAG node."""
    leaf = lambda: graph.node("s", 0)
    value = graph.node("p", leaf(), graph.node("p", leaf(), leaf()))
    for shift in range(width):
        value = graph.node("p", value, leaf()) if (index >> shift) & 1 \
            else graph.node("p", leaf(), value)
    return value


def _fresh_tree(graph: Any, depth: int, index: int, width: int) -> int:
    if depth == 0:
        value = _fresh_motif(graph, index, width)
        # No public node is shared even across these two beta identities.
        for _ in range(2):
            identity = graph.node("l", graph.node("s", 1), graph.node("v", 0))
            value = graph.node("a", identity, value)
        return value
    return graph.node("p", _fresh_tree(graph, depth - 1, index, width),
                      _fresh_tree(graph, depth - 1, index, width))


def _closed_annotation(graph: Any, count: int) -> int:
    return graph.beta_chain(count, graph.node("s", 2), graph.node("s", 1))


def fixture(name: str, count: int, dag_factory: DagFactory) -> Any:
    """Return a deterministic positive fixture using the supplied DAG factory."""
    _require_count(count)
    if name not in WORKLOADS:
        raise ValueError(f"unknown supplemental workload: {name}")
    graph = dag_factory()
    width = max(1, (count - 1).bit_length())

    if name == "distinct_trees":
        leaf = graph.beta_chain(4, graph.node("s", 1), graph.node("s", 0))
        for index in range(count):
            value = _tree(graph, 6, _motif(graph, index, width, leaf))
            ty = _closed_annotation(graph, 1 + index % 13)
            graph.definitions.append((f"distinct_{index:04d}", ty, value))

    elif name == "unshared_trees":
        for index in range(count):
            value = _fresh_tree(graph, 4, index, width)
            # A separate annotation is built for each definition as well.
            ty = _closed_annotation(graph, 1 + index % 7)
            graph.definitions.append((f"unshared_{index:04d}", ty, value))

    elif name == "dependent_terms":
        for index in range(count):
            binders = 1 + index % 24
            wrappers = 1 + index // 24
            # Under A : Sort 1 and the value binders, A has index `binders`,
            # and the outermost value x has index `binders - 1`.
            body = graph.node("v", binders - 1)
            for wrapper in range(wrappers):
                domain = graph.node("v", binders)
                if (index + wrapper) % 2:
                    body = graph.node("t", domain, body, graph.node("v", 0))
                else:
                    identity = graph.node("l", domain, graph.node("v", 0))
                    body = graph.node("a", identity, body)
            ty = graph.node("v", binders)
            for earlier in reversed(range(binders)):
                domain = graph.node("v", earlier)
                ty = graph.node("p", domain, ty)
                body = graph.node("l", domain, body)
            ty = graph.node("p", graph.node("s", 1), ty)
            body = graph.node("l", graph.node("s", 1), body)
            # These polymorphic function types inhabit Sort 2. The varying
            # beta wrapper also exercises conversion of declared annotations.
            ty = graph.beta_chain(index % 5, graph.node("s", 2), ty)
            graph.definitions.append((f"dependent_{index:04d}", ty, body))

    elif name == "alias_diamonds":
        for index in range(count):
            group, role = divmod(index, 4)
            prefix = f"diamond_{group:04d}"
            ty = _closed_annotation(graph, 1 + group % 7)
            if role == 0:
                leaf = graph.beta_chain(2, graph.node("s", 1), graph.node("s", 0))
                value = _tree(graph, 3, _motif(graph, group, width, leaf))
                suffix = "base"
            elif role in (1, 2):
                value = graph.node("c", prefix + "_base")
                suffix = "left" if role == 1 else "right"
            else:
                value = graph.node("p", graph.node("c", prefix + "_left"),
                                   graph.node("c", prefix + "_right"))
                suffix = "join"
            graph.definitions.append((prefix + "_" + suffix, ty, value))

    return graph


def refusal_fixtures(dag_factory: DagFactory) -> list[dict[str, Any]]:
    """Closed, parser-valid fixtures whose designated semantic error is required.

    A parser/resource failure is not a successful semantic-refusal observation.
    These are available to separate checks and are not timed positive workloads.
    """
    controls = []

    graph = dag_factory()
    sort = graph.node("s", 1)
    graph.definitions.append(("wrongDeclaredSort", sort, sort))
    controls.append({"name": "wrong_declared_type", "graph": graph,
                     "lean_error": "declTypeMismatch", "ocaml_error": "Type_mismatch"})

    graph = dag_factory()
    # fun A B x:A y:B => (fun z:A => z) y. The application uses y:B where A is
    # required. Every variable is in scope, so the intended error is semantic.
    value = graph.node("a", graph.node("l", graph.node("v", 3), graph.node("v", 0)),
                       graph.node("v", 0))
    ty = graph.node("v", 3)
    for domain in (graph.node("v", 1), graph.node("v", 1),
                   graph.node("s", 1), graph.node("s", 1)):
        value = graph.node("l", domain, value)
        ty = graph.node("p", domain, ty)
    graph.definitions.append(("wrongDependentArgument", ty, value))
    controls.append({"name": "wrong_dependent_argument", "graph": graph,
                     "lean_error": "appTypeMismatch", "ocaml_error": "Type_mismatch"})

    graph = dag_factory()
    annotation = graph.node("s", 1)
    value = graph.node("t", annotation, graph.node("c", "missingInErasedLet"), graph.node("s", 0))
    graph.definitions.append(("unusedUnknownConstant", annotation, value))
    controls.append({"name": "unused_unknown_constant", "graph": graph,
                     "lean_error": "unknownConstant", "ocaml_error": "Unknown_constant"})

    graph = dag_factory()
    annotation = graph.node("s", 1)
    value = graph.node("t", annotation, graph.node("s", 1), graph.node("s", 0))
    graph.definitions.append(("erasedIlltypedLet", annotation, value))
    controls.append({"name": "erased_illtyped_let", "graph": graph,
                     "lean_error": "letTypeMismatch", "ocaml_error": "Type_mismatch"})

    return controls


def metadata(name: str) -> dict[str, str]:
    if name not in DESCRIPTIONS:
        raise ValueError(f"unknown supplemental workload: {name}")
    return {"workload": name, "description": DESCRIPTIONS[name],
            "scope": "synthetic supplemental supported-fragment control; used during tuning; not representative Lean project evidence"}


def inventory(graph: Any) -> dict[str, int]:
    """Describe the encoded DAG without expanding it or invoking a checker."""
    heights: list[int] = []
    occurrences: list[int] = []
    for tag, fields in graph.nodes:
        children = fields if tag in {"a", "l", "p", "t"} else ()
        heights.append(1 + max((heights[int(x)] for x in children), default=0))
        occurrences.append(1 + sum(occurrences[int(x)] for x in children))
    roots = [node for _, ty, value in graph.definitions for node in (ty, value)]
    return {"definitions": len(graph.definitions), "dag_nodes": len(graph.nodes),
            "maximum_encoded_height": max(heights[root] for root in roots),
            "maximum_expanded_body_nodes": max(occurrences[value] for _, _, value in graph.definitions)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--definitions", type=int, default=128)
    args = parser.parse_args()
    _require_count(args.definitions)
    # The caller can import this module and pass its own Dag class without a
    # circular import. Import the factory here only for standalone generation.
    from compare_lean import Dag
    args.output.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, Any] = {
        "schema": "lean-ocaml.optimization-workloads.v1",
        "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "workloads": [], "refusal_controls": [],
    }
    for name in WORKLOADS:
        graph = fixture(name, args.definitions, Dag)
        path = args.output / f"{name}.tsv"
        path.write_text(graph.render())
        record = {**metadata(name), **inventory(graph), "path": path.name,
                  "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        manifest["workloads"].append(record)
    for control in refusal_fixtures(Dag):
        graph = control["graph"]
        path = args.output / f"refuse_{control['name']}.tsv"
        path.write_text(graph.render())
        record = {key: value for key, value in control.items() if key != "graph"}
        record.update(inventory(graph), path=path.name,
                      sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        manifest["refusal_controls"].append(record)
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
