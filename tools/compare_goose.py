#!/usr/bin/env python3
"""Compare the bounded Goose pilot, OCaml bytecode and the native Lean kernel.

All engines consume identical runtime DAG files. Successful independent
semantic checks are required before the first timing sample. This experiment
does not implement or certify a complete Lean kernel.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import platform
import random
import statistics
import tempfile

import compare_lean as baseline
import goose_common
import optimization_workloads
import test_goose

ROOT = baseline.ROOT


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--min-sample-seconds", type=float, default=0.15)
    parser.add_argument("--definitions", type=int, default=128)
    parser.add_argument("--workers", nargs="+", type=int, default=[1, 2, 4, 8])
    parser.add_argument("--output", type=Path, default=ROOT / "conformance/evidence/goose-comparison")
    args = parser.parse_args()
    if not (1 <= args.samples <= 30 and 1 <= args.definitions <= 512
            and math.isfinite(args.min_sample_seconds) and 0.05 <= args.min_sample_seconds <= 5):
        parser.error("samples 1..30, definitions 1..512, min-sample-seconds 0.05..5")
    if any(n < 1 or n > 64 for n in args.workers) or len(set(args.workers)) != len(args.workers):
        parser.error("workers must be distinct counts in 1..64")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    sources = goose_common.source_files()
    receipt = {
        "schema": "lean-ocaml.goose-migration-comparison.v1", "status": "running",
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "base_revision": baseline.command(["git", "rev-parse", "HEAD"]),
        "sources": sources, "samples_per_configuration": args.samples,
        "definitions_per_batch": args.definitions, "ocaml_workers": args.workers,
        "goose_workers": 1, "minimum_target_sample_seconds": args.min_sample_seconds,
        "machine": {"cpu_model": baseline.cpu_description(), "logical_cpus": os.cpu_count(),
                    "affinity_cpus": sorted(os.sched_getaffinity(0))
                    if hasattr(os, "sched_getaffinity") else None,
                    "platform": platform.platform()},
        "execution_order": "one measurement process at a time; deterministic shuffled configurations per round",
        "timing": "monotonic complete checked-batch intervals; fresh environment and caches per batch; parsing, source compilation, warmup and result validation untimed; process elapsed time also recorded",
        "scope": "synthetic transparent monomorphic definitions with numeric sorts and beta/zeta reduction; different bounded implementations, not a language-only causal comparison",
        "acceptance_authority": False, "authority": "unsigned_local_performance_observations_only",
        "calibrations": [], "observations": [],
    }

    def save() -> None:
        (output / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")

    save()
    try:
        with tempfile.TemporaryDirectory(prefix="goose-migration-") as folder:
            binaries, toolchains = goose_common.build_all(Path(folder))
            receipt["toolchains"] = toolchains
            conformance = test_goose.run_controls(binaries, output / "fixtures", args.definitions)
            receipt["conformance"] = {key: value for key, value in conformance.items() if key != "observations"}
            receipt["conformance"]["path"] = "fixtures/results.json"
            receipt["conformance"]["sha256"] = baseline.sha256(output / "fixtures/results.json")
            configurations = [
                ("lean-kernel", binaries["lean-kernel"], 1),
                ("goose-aot", binaries["goose-aot"], 1),
                *[("ocaml-bytecode", binaries["ocaml-bytecode"], workers) for workers in args.workers],
            ]
            receipt["fixtures"] = []
            for workload in test_goose.WORKLOADS:
                path = output / "fixtures" / f"{workload}.tsv"
                graph = (optimization_workloads.fixture(workload, args.definitions, baseline.Dag)
                         if workload in optimization_workloads.WORKLOADS
                         else baseline.fixture(workload, args.definitions))
                if path.read_text() != graph.render():
                    raise RuntimeError("semantic-control fixture differs from timing fixture")
                receipt["fixtures"].append({"workload": workload, "path": f"fixtures/{path.name}",
                                             "sha256": baseline.sha256(path),
                                             **optimization_workloads.inventory(graph)})
                iterations = {}
                for engine, binary, workers in configurations:
                    observation = baseline.measure(engine, binary, workers, path, 1, args.definitions)
                    count = max(1, min(100_000, math.ceil(
                        args.min_sample_seconds * 1e9 / observation["elapsed_ns"])))
                    iterations[(engine, workers)] = count
                    receipt["calibrations"].append({"workload": workload, **observation,
                                                    "selected_iterations": count})
                for sample in range(args.samples):
                    ordered = configurations.copy()
                    random.Random(20261119 + sample).shuffle(ordered)
                    for engine, binary, workers in ordered:
                        observation = baseline.measure(engine, binary, workers, path,
                                                       iterations[(engine, workers)], args.definitions)
                        receipt["observations"].append({"workload": workload, "sample": sample + 1,
                                                        **observation})
                        print(f"{workload} {engine} workers={workers} sample={sample + 1}: "
                              f"{observation['elapsed_ns'] / observation['iterations'] / 1e6:.6f} ms/batch "
                              f"({observation['iterations']} checked batches)", flush=True)
                        save()
            summaries = []
            for workload in test_goose.WORKLOADS:
                for engine, _, workers in configurations:
                    values = [r["elapsed_ns"] / r["iterations"] / 1e6 for r in receipt["observations"]
                              if (r["workload"], r["engine"], r["workers"]) == (workload, engine, workers)]
                    summaries.append({"workload": workload, "engine": engine, "workers": workers,
                                      "median_ms": statistics.median(values), "mean_ms": statistics.mean(values),
                                      "min_ms": min(values), "max_ms": max(values),
                                      "stdev_ms": statistics.stdev(values) if len(values) > 1 else 0.0})
            receipt["summaries"] = summaries
        receipt["source_unchanged_during_benchmark"] = goose_common.source_files() == sources
        if not receipt["source_unchanged_during_benchmark"]:
            raise RuntimeError("source changed during measurement")
        receipt["status"] = "passed"
        receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        save()
        print("\nMedian milliseconds per checked batch:", flush=True)
        for row in receipt["summaries"]:
            print(f"{row['workload']:16s} {row['engine']:15s} workers={row['workers']} "
                  f"{row['median_ms']:.6f} ms [{row['min_ms']:.6f}, {row['max_ms']:.6f}]")
    except Exception as error:
        receipt.update(status="failed", failure=str(error),
                       finished_at_utc=datetime.now(timezone.utc).isoformat())
        save()
        raise


if __name__ == "__main__":
    main()
