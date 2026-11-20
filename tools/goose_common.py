#!/usr/bin/env python3
"""Pinned toolchain and source handling shared by Goose migration checks."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil

import compare_lean as baseline

ROOT = baseline.ROOT
PIN = ROOT / "conformance/goose-toolchain.json"


def source_files() -> list[dict[str, object]]:
    paths = {item["path"] for item in baseline.source_files()}
    paths.update(str(p.relative_to(ROOT)) for p in (ROOT / "reference/goose").glob("*.goose"))
    paths.update({"conformance/migration_check.ml", "conformance/goose-toolchain.json",
                  "tools/goose_common.py", "tools/compare_goose.py", "tools/test_goose.py"})
    paths.update({"conformance/generated.tsv.types", "conformance/generated.tsv.defs"})
    return [{"path": name, "sha256": baseline.sha256(ROOT / name),
             "bytes": (ROOT / name).stat().st_size} for name in sorted(paths)]


def build_all(build: Path) -> tuple[dict[str, Path], dict[str, object]]:
    baseline.BUILD = build
    ocamlc = baseline.executable("OCAMLC", "ocamlc")
    lean = baseline.executable("LEAN", "lean")
    cc = baseline.executable("GOOSE_CC", "gcc")
    ocaml_version = (ROOT / ".ocaml-version").read_text().strip()
    if baseline.command([str(ocamlc), "-version"]) != ocaml_version:
        raise RuntimeError("OCaml compiler differs from pin")
    lean_version = baseline.command([str(lean), "--version"])
    provenance = json.loads((ROOT / "conformance/provenance.json").read_text())
    if (f"version {provenance['lean_release']}," not in lean_version
            or provenance["lean_commit"] not in lean_version):
        raise RuntimeError("Lean version or commit differs from pin")
    pin = json.loads(PIN.read_text())
    source = Path(os.environ.get("GOOSE_SOURCE", "")).expanduser().resolve()
    if not os.environ.get("GOOSE_SOURCE"):
        raise RuntimeError("set GOOSE_SOURCE to a built, pinned Goose checkout; see tools/build_goose.sh")
    revision = baseline.command(["git", "rev-parse", "HEAD"], cwd=source)
    if revision != pin["revision"]:
        raise RuntimeError(f"Goose source revision differs from pin: {revision}")
    if baseline.command(["git", "status", "--porcelain", "--untracked-files=no"], cwd=source):
        raise RuntimeError("Goose source checkout has tracked changes")
    goose = Path(os.environ.get("GOOSE", str(source / "build/goose"))).resolve()
    if not goose.is_file() or not os.access(goose, os.X_OK):
        raise RuntimeError(f"Goose executable is missing: {goose}")
    cc_version = baseline.command([str(cc), "--version"])
    if "gcc" not in cc_version.lower() and "free software foundation" not in cc_version.lower():
        raise RuntimeError("this comparison pins the GCC backend; set GOOSE_CC to gcc")
    print("Building Goose AOT, OCaml bytecode and native Lean drivers (untimed).", flush=True)
    ocaml_binary = baseline.build_ocaml(ocamlc)
    lean_binary = baseline.build_lean(lean)
    ocaml_folder = build / "bytecode"
    shutil.copyfile(ROOT / "conformance/migration_check.ml", ocaml_folder / "migration_check.ml")
    ocaml_checker = ocaml_folder / "migration_check"
    baseline.command([str(ocamlc), "-o", str(ocaml_checker), "conversion.cmo", "migration_check.ml"],
                     cwd=ocaml_folder)
    folder = build / "goose"
    folder.mkdir()
    generated = folder / "benchmark.c"
    goose_binary = folder / "benchmark_goose"
    emit_command = [str(goose), *pin["goose_flags"], "-o", str(generated),
                    str(ROOT / "reference/goose/benchmark.goose")]
    baseline.command(emit_command)
    emitted = generated.read_text()
    if "#define GS_DEBUG 1" not in emitted:
        raise RuntimeError("generated C does not retain requested GS_DEBUG=1 checks")
    compile_command = [str(cc), "-O2", str(generated), "-o", str(goose_binary), "-lm", "-pthread"]
    baseline.command(compile_command)
    binaries = {"lean-kernel": lean_binary, "ocaml-bytecode": ocaml_binary,
                "ocaml-check": ocaml_checker, "goose-aot": goose_binary}
    toolchains = {
        "ocaml_version": ocaml_version, "ocaml_backend": "bytecode", "lean_version": lean_version,
        "goose": {**pin, "source_checkout": str(source), "tracked_source_clean": True,
                  "source_revision": revision, "compiler": str(goose),
                  "compiler_sha256": baseline.sha256(goose),
                  "generated_c_sha256": baseline.sha256(generated),
                  "generated_c_bytes": generated.stat().st_size,
                  "emit_command": emit_command, "compile_command": compile_command,
                  "gcc_version": cc_version},
        "executables": [{"path": str(p), "sha256": baseline.sha256(p)}
                        for p in (ocamlc, lean, lean.parent / "leanc", cc)],
        "binaries": [{"engine": engine, "sha256": baseline.sha256(binary)}
                     for engine, binary in binaries.items()],
    }
    return binaries, toolchains
