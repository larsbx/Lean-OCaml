#!/usr/bin/env python3
"""Differential admission observations for the bounded Goose experiment.

Reuses the committed 40 typing vectors and six definition insertions, adds
post-refusal observations, and checks all seven matched benchmark workloads.
Resource, parser and internal failures never satisfy semantic expectations.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import tempfile

import compare_lean as baseline
import goose_common
import optimization_workloads

ROOT = baseline.ROOT
WORKLOADS = ("wide", "chain", "identities", *optimization_workloads.WORKLOADS)


def decode(graph: baseline.Dag, text: str) -> int:
    tokens = iter(text.split())

    def parse() -> int:
        token = next(tokens)
        if token in ("a", "l", "p"):
            return graph.node(token, parse(), parse())
        if token == "t":
            return graph.node(token, parse(), parse(), parse())
        if token[0] in ("s", "v"):
            return graph.node(token[0], int(token[1:]))
        if token[0] == "c":
            return graph.node("c", token[1:])
        raise ValueError(f"unknown expression token: {token}")

    result = parse()
    if next(tokens, None) is not None:
        raise ValueError("trailing expression tokens")
    return result


def expected_row(name: str, outcome: str) -> dict[str, str]:
    return {"name": name, "outcome": outcome}


def controls() -> list[tuple[str, baseline.Dag, list[dict[str, str]], list[dict[str, str]]]]:
    cases = []
    typing_errors = {
        "nonfunction": ("Expected_function", "funExpected"),
        "argument-mismatch": ("Type_mismatch", "appTypeMismatch"),
        "let-mismatch": ("Type_mismatch", "letTypeMismatch"),
        "binder-not-type": ("Expected_sort", "typeExpected"),
        "pi-body-not-type": ("Expected_sort", "typeExpected"),
    }
    graph = baseline.Dag()
    reference, lean = [], []
    for line in (ROOT / "conformance/generated.tsv.types").read_text().splitlines():
        tag, name, value, ty = line.split("\t")
        if tag != "type":
            raise ValueError("unexpected typing schema")
        label = "typing_" + name.replace("-", "_")
        body = decode(graph, value)
        annotation = decode(graph, ty if ty != "refused" else "s0")
        graph.definitions.append((label, annotation, body))
        outcomes = (("Type_mismatch", "appTypeMismatch") if "wrong-binder" in name
                    else typing_errors[name]) if ty == "refused" else ("accepted", "accepted")
        reference.append(expected_row(label, outcomes[0]))
        lean.append(expected_row(label, outcomes[1]))
    cases.append(("committed_typing_vectors", graph, reference, lean))

    graph = baseline.Dag()
    reference, lean = [], []
    definition_errors = {
        "ocamlRefAlias": ("Duplicate_definition", "alreadyDeclared"),
        "ocamlRefMissing": ("Unknown_constant", "unknownConstant"),
        "ocamlRefMismatch": ("Type_mismatch", "declTypeMismatch"),
        "ocamlRefNonType": ("Expected_sort", "typeExpected"),
    }
    for line in (ROOT / "conformance/generated.tsv.defs").read_text().splitlines():
        fields = line.split("\t")
        if fields[0] == "infer":
            # The final historical inference becomes a checked alias with the
            # exact expected type, preserving the semantic observation.
            _, value, ty = fields
            name, expected = "afterRefusalId", "true"
        else:
            _, name, ty, value, expected = fields
        graph.definitions.append((name, decode(graph, ty), decode(graph, value)))
        outcomes = ("accepted", "accepted") if expected == "true" else definition_errors[name]
        reference.append(expected_row(name, outcomes[0]))
        lean.append(expected_row(name, outcomes[1]))
    for name, ty, value, outcomes in [
        ("refusedNameAbsent", "s1", "cocamlRefMismatch", ("Unknown_constant", "unknownConstant")),
        ("oldAliasPreserved", "s1", "cocamlRefAlias", ("accepted", "accepted")),
        ("reusedRefusedName", "s1", "s1", ("Type_mismatch", "declTypeMismatch")),
        ("reusedRefusedName", "s1", "s0", ("accepted", "accepted")),
        ("useReusedName", "s1", "creusedRefusedName", ("accepted", "accepted")),
    ]:
        graph.definitions.append((name, decode(graph, ty), decode(graph, value)))
        reference.append(expected_row(name, outcomes[0]))
        lean.append(expected_row(name, outcomes[1]))
    cases.append(("committed_definitions_and_refusal_state", graph, reference, lean))

    for control in optimization_workloads.refusal_fixtures(baseline.Dag):
        graph = control["graph"]
        name = graph.definitions[0][0]
        cases.append((control["name"], graph,
                      [expected_row(name, control["ocaml_error"])],
                      [expected_row(name, control["lean_error"])]))
    # These annotations distinguish beta/zeta reduction in types from unchecked
    # equality or an implementation which drops annotations before checking.
    graph = baseline.Dag()
    terms = [
        ("betaAnnotation", "a l s2 v0 s1", "s0", "accepted", "accepted"),
        ("wrongBetaAnnotation", "a l s3 v0 s2", "s0", "Type_mismatch", "declTypeMismatch"),
        ("hiddenBadAnnotation", "a l s2 s1 s0", "s0", "Type_mismatch", "appTypeMismatch"),
        ("hiddenBadArgument", "s1", "a l s1 s0 s1", "Type_mismatch", "appTypeMismatch"),
        ("impredicative", "s0", "p s1 p s0 v0", "accepted", "accepted"),
    ]
    reference, lean = [], []
    for name, ty, value, ref_outcome, lean_outcome in terms:
        graph.definitions.append((name, decode(graph, ty), decode(graph, value)))
        reference.append(expected_row(name, ref_outcome))
        lean.append(expected_row(name, lean_outcome))
    cases.append(("annotation_and_erasure_controls", graph, reference, lean))

    # The *same* open application node occurs under two different contexts.
    # Caching its first inferred type without the context would accept the bad
    # second declaration. Prefix strings alone would allocate separate nodes.
    graph = baseline.Dag()
    sort = graph.node("s", 1)
    v0, v1, v2 = (graph.node("v", i) for i in range(3))
    shared = graph.node("a", graph.node("l", v2, v0), v0)
    reference, lean = [], []
    for name, domain, outcome, lean_outcome in [
        ("sharedOpenGood", v1, "accepted", "accepted"),
        ("sharedOpenBad", v0, "Type_mismatch", "appTypeMismatch"),
        ("sharedOpenGoodAgain", v1, "accepted", "accepted"),
    ]:
        ty = graph.node("p", sort, graph.node("p", sort, graph.node("p", domain, v2)))
        value = graph.node("l", sort, graph.node("l", sort, graph.node("l", domain, shared)))
        graph.definitions.append((name, ty, value))
        reference.append(expected_row(name, outcome))
        lean.append(expected_row(name, lean_outcome))
    for name, ty, outcome, lean_outcome in [
        ("captureAvoided", "p s1 p s1 p v1 p v1 v3", "accepted", "accepted"),
        ("captureWrongType", "p s1 p s1 p v1 p v1 v2", "Type_mismatch", "declTypeMismatch"),
    ]:
        graph.definitions.append((name, decode(graph, ty),
                                  decode(graph, "l s1 l s1 l v1 a l v2 l v2 v1 v0")))
        reference.append(expected_row(name, outcome))
        lean.append(expected_row(name, lean_outcome))
    cases.append(("context_reuse_and_capture", graph, reference, lean))

    # Register the intentionally smaller conversion relation explicitly. Each
    # equality specimen is lifted into the argument of a dependent type family;
    # checking the declaration requires eta or proof irrelevance in Lean.
    graph = baseline.Dag()
    reference, lean = [], []
    for name, operand_type, left, right in [
        ("etaBoundary", "p p s1 s1 p s1 s1", "l p s1 s1 v0", "l p s1 s1 l s1 a v1 v0"),
        ("proofIrrelevanceBoundary", "p s0 p v0 p v1 v2",
         "l s0 l v0 l v1 v1", "l s0 l v0 l v1 v0"),
    ]:
        family = graph.node("p", decode(graph, operand_type), graph.node("s", 1))
        lhs, rhs = decode(graph, left), decode(graph, right)
        family0, family1 = graph.node("v", 0), graph.node("v", 1)
        ty = graph.node("p", family,
                        graph.node("p", graph.node("a", family0, rhs), graph.node("a", family1, rhs)))
        value = graph.node("l", family,
                           graph.node("l", graph.node("a", family0, lhs), graph.node("v", 0)))
        graph.definitions.append((name, ty, value))
        reference.append(expected_row(name, "Type_mismatch"))
        lean.append(expected_row(name, "accepted"))
    cases.append(("registered_conversion_boundaries", graph, reference, lean))
    return cases


def check_result(engine: str, binary: Path, path: Path, expected: list[dict[str, str]]) -> dict:
    result = json.loads(baseline.command([str(binary), "--check", str(path)]))
    if (result.get("engine") != engine or result.get("status") != "checked"
            or result.get("outcomes") != expected
            or result.get("accepted") != sum(row["outcome"] == "accepted" for row in expected)
            or result.get("acceptance_authority") is not False):
        raise RuntimeError(f"{engine} differential mismatch on {path.name}: {result!r}; expected {expected!r}")
    if engine == "lean-kernel" and (result.get("trust_level") != 0
                                    or result.get("checked_insertion") is not True):
        raise RuntimeError("Lean control did not establish checked insertion at trust level zero")
    return result


def structural_controls(binary: Path, output: Path) -> list[dict]:
    header = "lean-ocaml-benchmark-dag-v1\n"
    graph = baseline.Dag()
    sort = graph.node("s", 1)
    body = graph.node("s", 0)
    for _ in range(129):
        body = graph.node("p", sort, body)
    graph.definitions.append(("tooDeep", sort, body))
    specimens = [
        ("forward_reference", header + "n\t0\ta\t0\t0\nd\tx\t0\t0\n", 3, "node reference must precede"),
        ("negative_index", header + "n\t0\tv\t-1\nd\tx\t0\t0\n", 3, "invalid natural"),
        ("unknown_tag", header + "n\t0\tq\t0\nd\tx\t0\t0\n", 3, "unknown node tag"),
        ("missing_lf", header + "n\t0\ts\t0\nd\tx\t0\t0", 3, "missing final LF"),
        ("height_limit", graph.render(), 2, "Height_limit"),
        ("loose_variable", header + "n\t0\ts\t1\nn\t1\tv\t0\nd\tx\t0\t1\n", 2, "Invalid_scope"),
    ]
    results = []
    for name, contents, code, diagnostic in specimens:
        path = output / f"invalid_{name}.tsv"
        path.write_text(contents)
        result = subprocess.run([str(binary), "--check", str(path)], text=True,
                                capture_output=True, timeout=30)
        if result.returncode != code or diagnostic not in result.stderr or result.stdout.strip():
            raise RuntimeError(f"structural/resource control failed: {name}: {result!r}")
        results.append({"name": name, "fixture": path.name, "sha256": baseline.sha256(path),
                        "exit_code": result.returncode, "stderr": result.stderr.strip(), "status": "passed"})
    return results


def run_controls(binaries: dict[str, Path], output: Path, definitions: int = 128) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    cases = controls()
    for workload in WORKLOADS:
        graph = (optimization_workloads.fixture(workload, definitions, baseline.Dag)
                 if workload in optimization_workloads.WORKLOADS else baseline.fixture(workload, definitions))
        expected = [expected_row(name, "accepted") for name, _, _ in graph.definitions]
        cases.append((workload, graph, expected, expected))
    observations = []
    for name, graph, reference, lean in cases:
        path = output / f"{name}.tsv"
        path.write_text(graph.render())
        results = []
        for engine, key, expected in [("lean-kernel", "lean-kernel", lean),
                                      ("ocaml-bytecode", "ocaml-check", reference),
                                      ("goose-aot", "goose-aot", reference)]:
            results.append(check_result(engine, binaries[key], path, expected))
        observations.append({"case": name, "fixture": path.name, "sha256": baseline.sha256(path),
                             "definitions": len(graph.definitions), "engines": results})
        print(f"Migration conformance: {name}: {len(graph.definitions)} ordered outcomes match registered expectations.", flush=True)
    invalid = structural_controls(binaries["goose-aot"], output)
    result = {"schema": "lean-ocaml.goose-conformance.v1", "status": "passed",
              "acceptance_authority": False, "fixtures": len(cases),
              "ordered_outcomes_per_engine": sum(len(case[1].definitions) for case in cases),
              "registered_disagreements": ["etaBoundary", "proofIrrelevanceBoundary"],
              "structural_and_resource_controls": invalid,
              "observations": observations}
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "conformance/evidence/goose-conformance")
    parser.add_argument("--definitions", type=int, default=128)
    args = parser.parse_args()
    if not 1 <= args.definitions <= 512:
        parser.error("definitions must be in 1..512")
    before = goose_common.source_files()
    with tempfile.TemporaryDirectory(prefix="goose-conformance-") as folder:
        binaries, toolchains = goose_common.build_all(Path(folder))
        result = run_controls(binaries, args.output.resolve(), args.definitions)
    result.update(sources=before, toolchains=toolchains,
                  source_unchanged=goose_common.source_files() == before,
                  finished_at_utc=datetime.now(timezone.utc).isoformat())
    if not result["source_unchanged"]:
        raise RuntimeError("source changed during conformance")
    (args.output / "results.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
