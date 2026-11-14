#!/usr/bin/env python3
"""Verify immutable-source artifacts; this is not a trust attestation."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_PATHS = {
    "conformance/rust-v1.tsv", "oracles/RustBaseline.lean",
    "docs/rust-v1-correspondence.md", "oracles/Generate.lean",
    "conformance/generated.tsv", "conformance/generated.tsv.types",
    "conformance/generated.tsv.defs",
}

def verify() -> None:
    manifest = json.loads((ROOT / "conformance/provenance.json").read_text())
    if manifest["schema"] != "lean-ocaml.source-provenance.v1":
        raise ValueError("unknown source-provenance schema")
    records = manifest["files"]
    if len(records) != len(EXPECTED_PATHS) or {r["path"] for r in records} != EXPECTED_PATHS:
        raise ValueError("missing, duplicate or unexpected provenance paths")
    for record in records:
        path = ROOT / record["path"]
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"expected regular source file: {record['path']}")
        if not re.fullmatch(r"[0-9a-f]{40}", record["revision"]):
            raise ValueError(f"unfixed source revision: {record['path']}")
        expected_url = (f"https://github.com/{record['repository']}/blob/"
                        f"{record['revision']}/{record['upstream_path']}")
        if record["source_url"] != expected_url or record["copied_byte_for_byte"] is not True:
            raise ValueError(f"inconsistent source mapping: {record['path']}")
        data = path.read_bytes()
        blob = b"blob " + str(len(data)).encode() + b"\0" + data
        if hashlib.sha256(data).hexdigest() != record["sha256"]:
            raise ValueError(f"SHA-256 mismatch: {record['path']}")
        if hashlib.sha1(blob).hexdigest() != record["git_blob_sha1"]:
            raise ValueError(f"Git blob mismatch: {record['path']}")
    if (ROOT / ".ocaml-version").read_text().strip() != manifest["ocaml_version"]:
        raise ValueError("OCaml version differs from provenance")
    if (ROOT / "lean-toolchain").read_text().strip() != "leanprover/lean4:v" + manifest["lean_release"]:
        raise ValueError("Lean version differs from provenance")
    counts = {"conformance/rust-v1.tsv": 19, "conformance/generated.tsv": 144,
              "conformance/generated.tsv.types": 40, "conformance/generated.tsv.defs": 7}
    for path, count in counts.items():
        if len((ROOT / path).read_text().splitlines()) != count:
            raise ValueError(f"fixture count changed: {path}")
    print("Source provenance passed: 7 byte-identical source artifacts, pinned toolchains and corpus counts")

if __name__ == "__main__":
    try:
        verify()
    except (OSError, KeyError, TypeError, ValueError) as error:
        print(f"Source provenance refused: {error}", file=sys.stderr)
        sys.exit(1)
