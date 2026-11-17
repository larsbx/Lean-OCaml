#!/usr/bin/env python3
"""Run local acceptance and bind observations to the exact source bytes."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "conformance/evidence"
SKIP_DIRS = {".git", "_build", "__pycache__"}
SKIP_SUFFIXES = {".cmi", ".cmo", ".cmx", ".o", ".pyc"}

def source_snapshot() -> tuple[list[dict[str, object]], str]:
    files = []
    def fail_walk(error: OSError) -> None:
        raise error
    for parent, directories, names in os.walk(ROOT, onerror=fail_walk):
        for directory in directories:
            if (Path(parent) / directory).is_symlink():
                raise ValueError(f"source directory symlink is outside the receipt contract: {Path(parent) / directory}")
        directories[:] = sorted(d for d in directories if d not in SKIP_DIRS
                                and Path(parent) / d != EVIDENCE)
        for name in sorted(names):
            path = Path(parent) / name
            if path.suffix in SKIP_SUFFIXES:
                continue
            if path.is_symlink():
                raise ValueError(f"source symlink is outside the receipt contract: {path}")
            # A linked worktree uses a .git file instead of a directory. Neither
            # representation is source, and the file contains a local path.
            if name == ".git":
                continue
            content = path.read_bytes()
            files.append({"path": path.relative_to(ROOT).as_posix(),
                          "bytes": len(content),
                          "sha256": hashlib.sha256(content).hexdigest()})
    files.sort(key=lambda item: item["path"])
    encoded = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return files, hashlib.sha256(encoded).hexdigest()

def command_output(command: list[str]) -> str:
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=15)
        return (result.stdout + result.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as error:
        return str(error)

def run(command: list[str], logfile: Path) -> dict[str, object]:
    started = datetime.now(timezone.utc).isoformat()
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
        output = result.stdout + result.stderr
        status, code = ("passed" if result.returncode == 0 else "failed"), result.returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        output, status, code = str(error) + "\n", "prerequisite_or_execution_failure", None
    logfile.write_text(output)
    print(output, end="", flush=True)
    return {"command": command, "started_at_utc": started,
            "finished_at_utc": datetime.now(timezone.utc).isoformat(),
            "status": status, "exit_code": code,
            "log": logfile.relative_to(ROOT).as_posix(),
            "log_sha256": hashlib.sha256(logfile.read_bytes()).hexdigest()}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lean", action="store_true", help="regenerate both pinned Lean corpora")
    parser.add_argument("--benchmark", action="store_true",
                        help="record reproducible concurrency measurements; no speed threshold")
    parser.add_argument("--audit", type=Path, help="external pinned estate auditor (offline)")
    args = parser.parse_args()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    files, source_digest = source_snapshot()
    git_root = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT,
                              capture_output=True, text=True)
    baseline = None
    if git_root.returncode == 0 and Path(git_root.stdout.strip()).resolve() == ROOT:
        revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                                  capture_output=True, text=True)
        if revision.returncode == 0:
            baseline = revision.stdout.strip()
    ocaml = os.environ.get("OCAMLC", "ocamlc")
    lean = os.environ.get("LEAN", "lean")
    receipt: dict[str, object] = {
        "schema": "lean-ocaml.local-acceptance.v1",
        "base_revision": baseline,
        "source_tree_sha256": source_digest,
        "source_manifest": "conformance/evidence/source-manifest.json",
        "evidence_directory_excluded_from_source_digest": "conformance/evidence/",
        "source_digest_encoding": "SHA-256 of sorted file objects with path, bytes, sha256; canonical compact JSON with sorted keys",
        "ocaml_executable": ocaml,
        "ocaml_version": command_output([ocaml, "-version"]),
        "lean_executable": lean,
        "lean_version": command_output([lean, "--version"]),
        "lean_regeneration_requested": args.lean,
        "benchmark_requested": args.benchmark,
        "hosted_acceptance_included": False,
        "authority": "unsigned_local_test_observations_only",
        "checks": [],
    }
    (EVIDENCE / "source-manifest.json").write_text(json.dumps(files, indent=2) + "\n")
    checks = receipt["checks"]
    assert isinstance(checks, list)
    replay = ["sh", "conformance/run.sh"] + (["--lean"] if args.lean else [])
    checks.append(run(replay, EVIDENCE / "conformance.log"))
    audit = ["sh", "tools/estate-audit.sh"]
    if args.audit:
        audit.append(str(args.audit.resolve()))
    checks.append(run(audit, EVIDENCE / "estate-audit.log"))
    if args.benchmark:
        checks.append(run(["sh", "tools/benchmark.sh", "--scale", "4", "--repetitions", "5"],
                          EVIDENCE / "benchmark.log"))
    after_files, after_digest = source_snapshot()
    receipt["source_unchanged_during_acceptance"] = after_files == files and after_digest == source_digest
    receipt["status"] = ("passed" if all(c["status"] == "passed" for c in checks)
                         and receipt["source_unchanged_during_acceptance"] else "failed")
    receipt["completed_at_utc"] = datetime.now(timezone.utc).isoformat()
    (EVIDENCE / "acceptance.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Local acceptance {receipt['status']}; source SHA-256 {source_digest}")
    return 0 if receipt["status"] == "passed" else 1

if __name__ == "__main__":
    raise SystemExit(main())
