#!/usr/bin/env python3
"""Clock OCaml bytecode for the supported fragment against Lean's real kernel.

Builds are untimed. Both drivers decode the same DAG outside their timers.
Reported samples time checked batches, not elaboration or entire processes.
"""
from __future__ import annotations

import argparse
import atexit
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import shutil
import statistics
import subprocess
import tempfile
import time

import optimization_workloads

ROOT = Path(__file__).resolve().parents[1]
# Build products never enter the governed source layout and are removed on exit.
BUILD: Path
DEFAULT_OUTPUT = ROOT / "conformance/evidence/lean-comparison"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args: list[str], cwd: Path = ROOT, timeout: int = 300) -> str:
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"command failed: {args!r}\n{result.stdout}{result.stderr}")
    return result.stdout.strip()


def executable(variable: str, default: str) -> Path:
    name = os.environ.get(variable, default)
    found = shutil.which(name)
    if not found:
        raise RuntimeError(f"missing {name}; set {variable}")
    return Path(found).absolute()


class Dag:
    def __init__(self) -> None:
        self.nodes: list[tuple[str, tuple[object, ...]]] = []
        self.definitions: list[tuple[str, int, int]] = []

    def node(self, tag: str, *fields: object) -> int:
        self.nodes.append((tag, fields))
        return len(self.nodes) - 1

    def beta_chain(self, count: int, domain: int, value: int) -> int:
        for _ in range(count):
            identity = self.node("l", domain, self.node("v", 0))
            value = self.node("a", identity, value)
        return value

    def render(self) -> str:
        rows = ["lean-ocaml-benchmark-dag-v1"]
        rows.extend("\t".join(map(str, ("n", index, tag, *fields)))
                    for index, (tag, fields) in enumerate(self.nodes))
        rows.extend("\t".join(map(str, ("d", *entry))) for entry in self.definitions)
        return "\n".join(rows) + "\n"


def fixture(workload: str, count: int) -> Dag:
    graph = Dag()
    if workload == "identities":
        domain = graph.node("s", 1)
        ty = graph.node("p", domain, domain)
        value = graph.node("l", domain, graph.node("v", 0))
    else:
        value = graph.beta_chain(4, graph.node("s", 1), graph.node("s", 0))
        for _ in range(9):
            value = graph.node("p", value, value)
        ty = graph.beta_chain(16, graph.node("s", 2), graph.node("s", 1))
    for index in range(count):
        body = graph.node("c", f"{workload}_{index - 1:04d}") \
            if workload == "chain" and index else value
        graph.definitions.append((f"{workload}_{index:04d}", ty, body))
    return graph


def build_ocaml(compiler: Path) -> Path:
    folder = BUILD / "bytecode"
    folder.mkdir(parents=True, exist_ok=True)
    modules = ["conversion", "bounded_parallel", "definition_batch"]
    for module in modules:
        for suffix in (".ml", ".mli"):
            shutil.copyfile(ROOT / "reference" / (module + suffix), folder / (module + suffix))
    for name in ("benchmark_compare.ml", "benchmark_clock.c"):
        shutil.copyfile(ROOT / "conformance" / name, folder / name)
    for module in modules:
        for suffix in (".mli", ".ml"):
            command([str(compiler), "-c", module + suffix], cwd=folder)
    command([str(compiler), "-c", "benchmark_clock.c"], cwd=folder)
    output = folder / "benchmark_compare"
    command([str(compiler), "-custom", "-o", str(output),
             *(module + ".cmo" for module in modules), "benchmark_compare.ml", "benchmark_clock.o"],
            cwd=folder)
    return output


def build_lean(lean: Path) -> Path:
    folder = BUILD / "lean"
    folder.mkdir(parents=True, exist_ok=True)
    source = folder / "BenchmarkKernel.c"
    output = folder / "benchmark_kernel"
    command([str(lean), "-c", str(source), "oracles/BenchmarkKernel.lean"])
    command([str(lean.parent / "leanc"), "-O3", "-o", str(output), str(source)])
    return output


def cpu_description() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor()


def source_files() -> list[dict[str, object]]:
    paths = [*sorted((ROOT / "reference").glob("*.ml")),
             *sorted((ROOT / "reference").glob("*.mli")),
             ROOT / "conformance/benchmark_compare.ml", ROOT / "conformance/benchmark_clock.c",
             ROOT / "oracles/BenchmarkKernel.lean", ROOT / "tools/compare_lean.py",
             ROOT / "tools/optimization_workloads.py"]
    return [{"path": str(path.relative_to(ROOT)), "sha256": sha256(path),
             "bytes": path.stat().st_size} for path in sorted(paths)]


def measure(engine: str, binary: Path, workers: int, path: Path,
            iterations: int, expected_definitions: int) -> dict[str, object]:
    args = [str(binary), str(path)]
    if engine != "lean-kernel":
        args.append(str(workers))
    args.append(str(iterations))
    start = time.perf_counter_ns()
    output = command(args)
    process_ns = time.perf_counter_ns() - start
    observation = json.loads(output)
    if (observation.get("status") != "passed" or observation.get("engine") != engine
            or observation.get("iterations") != iterations
            or observation.get("definitions") != expected_definitions
            or observation.get("validated_batches") != iterations
            or observation.get("refusal_controls") != 1
            or observation.get("elapsed_ns", 0) <= 0):
        raise RuntimeError(f"invalid or failed sample: {observation!r}")
    if engine == "lean-kernel" and (observation.get("trust_level") != 0
                                    or observation.get("checked_insertion") is not True):
        raise RuntimeError("Lean did not establish checked insertion at trust level zero")
    observation.update(workers=workers, process_elapsed_ns=process_ns, command=args)
    return observation


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=7)
    parser.add_argument("--min-sample-seconds", type=float, default=0.15)
    parser.add_argument("--definitions", type=int, default=128)
    parser.add_argument("--workers", nargs="+", type=int, default=[1, 2, 4, 8])
    parser.add_argument("--workloads", nargs="+",
                        choices=["wide", "chain", "identities", *optimization_workloads.WORKLOADS],
                        default=["wide", "chain", "identities"])
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if not (1 <= args.samples <= 30 and 1 <= args.definitions <= 512
            and 0.05 <= args.min_sample_seconds <= 5):
        parser.error("samples 1..30, definitions 1..512, min-sample-seconds 0.05..5")
    if any(n < 1 or n > 64 for n in args.workers) or len(set(args.workers)) != len(args.workers):
        parser.error("workers must be distinct counts in 1..64")
    if len(set(args.workloads)) != len(args.workloads):
        parser.error("workloads must be distinct")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    global BUILD
    build_context = tempfile.TemporaryDirectory(prefix="lean-ocaml-comparison-")
    BUILD = Path(build_context.name)
    atexit.register(build_context.cleanup)
    ocamlc = executable("OCAMLC", "ocamlc")
    lean = executable("LEAN", "lean")
    ocaml_version = (ROOT / ".ocaml-version").read_text().strip()
    if command([str(ocamlc), "-version"]) != ocaml_version:
        raise RuntimeError("OCaml compiler differs from pin")
    lean_version = command([str(lean), "--version"])
    provenance = json.loads((ROOT / "conformance/provenance.json").read_text())
    if (f"version {provenance['lean_release']}," not in lean_version
            or provenance["lean_commit"] not in lean_version):
        raise RuntimeError("Lean version or commit differs from pin")
    sources_before = source_files()
    print("Building OCaml bytecode and the native Lean kernel benchmark driver.", flush=True)
    build_ocaml(ocamlc)
    build_lean(lean)
    configurations = [
        ("lean-kernel", BUILD / "lean/benchmark_kernel", 1),
        *[("ocaml-bytecode", BUILD / "bytecode/benchmark_compare", workers)
          for workers in args.workers],
    ]
    workloads = args.workloads
    fixtures = []
    for workload in workloads:
        graph = (optimization_workloads.fixture(workload, args.definitions, Dag)
                 if workload in optimization_workloads.WORKLOADS
                 else fixture(workload, args.definitions))
        path = output / f"{workload}.tsv"
        path.write_text(graph.render())
        fixtures.append({"workload": workload, "path": path.name, "sha256": sha256(path),
                         **optimization_workloads.inventory(graph),
                         **(optimization_workloads.metadata(workload)
                            if workload in optimization_workloads.WORKLOADS else {})})
    receipt: dict[str, object] = {
        "schema": "lean-ocaml.vs-lean-kernel.v1", "status": "running",
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "baseline_revision": command(["git", "rev-parse", "HEAD"]),
        "sources": sources_before, "fixtures": fixtures,
        "ocaml_version": ocaml_version, "ocaml_backend": "bytecode", "lean_version": lean_version,
        "toolchains": [{"path": str(path), "sha256": sha256(path)}
                       for path in (ocamlc, lean, lean.parent / "leanc")],
        "binaries": [{"engine": engine, "path": str(binary),
                      "sha256": sha256(binary)} for engine, binary in [
                          ("lean-kernel", BUILD / "lean/benchmark_kernel"),
                          ("ocaml-bytecode", BUILD / "bytecode/benchmark_compare")]],
        "machine": {"cpu_model": cpu_description(), "logical_cpus": os.cpu_count(),
                    "affinity_cpus": sorted(os.sched_getaffinity(0))
                    if hasattr(os, "sched_getaffinity") else None,
                    "platform": platform.platform()},
        "samples_per_configuration": args.samples,
        "ocaml_workers": args.workers,
        "minimum_target_sample_seconds": args.min_sample_seconds,
        "execution_order": "one process at a time; deterministic shuffled configurations per round",
        "timing": "sum of monotonic complete-batch intervals; fresh environment each batch; parsing, construction, verification and OCaml full GC outside",
        "scope": "synthetic transparent monomorphic definitions in the shared supported fragment",
        "authority": "unsigned_local_performance_observations_only",
        "calibrations": [], "observations": [],
    }
    records = receipt["observations"]
    for workload in workloads:
        path = output / f"{workload}.tsv"
        iterations_by_configuration = {}
        for engine, binary, workers in configurations:
            observation = measure(engine, binary, workers, path, 1, args.definitions)
            count = max(1, min(100_000, math.ceil(
                args.min_sample_seconds * 1e9 / observation["elapsed_ns"])))
            iterations_by_configuration[(engine, workers)] = count
            receipt["calibrations"].append({"workload": workload, **observation,
                                             "selected_iterations": count})
        for sample in range(args.samples):
            ordered = configurations.copy()
            random.Random(20261117 + sample).shuffle(ordered)
            for engine, binary, workers in ordered:
                count = iterations_by_configuration[(engine, workers)]
                observation = measure(engine, binary, workers, path, count, args.definitions)
                records.append({"workload": workload, "sample": sample + 1, **observation})
                print(f"{workload} {engine} workers={workers} sample={sample + 1}: "
                      f"{observation['per_batch_ns'] / 1e6:.6f} ms/batch "
                      f"({count} checked batches)", flush=True)
                (output / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
    summaries = []
    for workload in workloads:
        for engine, _, workers in configurations:
            values = [r["elapsed_ns"] / r["iterations"] / 1e6 for r in records
                      if (r["workload"], r["engine"], r["workers"]) == (workload, engine, workers)]
            summaries.append({"workload": workload, "engine": engine, "workers": workers,
                              "median_ms": statistics.median(values), "mean_ms": statistics.mean(values),
                              "min_ms": min(values), "max_ms": max(values),
                              "stdev_ms": statistics.stdev(values) if len(values) > 1 else 0.0})
    receipt["summaries"] = summaries
    receipt["source_unchanged_during_benchmark"] = source_files() == sources_before
    if not receipt["source_unchanged_during_benchmark"]:
        raise RuntimeError("source changed during measurements")
    receipt["status"] = "passed"
    receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    (output / "results.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("\nMedian milliseconds per checked batch:", flush=True)
    for row in summaries:
        print(f"{row['workload']:10s} {row['engine']:15s} workers={row['workers']} "
              f"{row['median_ms']:.6f} ms [{row['min_ms']:.6f}, {row['max_ms']:.6f}]")


if __name__ == "__main__":
    main()
