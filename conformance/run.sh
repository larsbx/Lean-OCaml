#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
case "$#:${1:-}" in
  0:) regenerate=false ;;
  1:--lean) regenerate=true ;;
  *) printf '%s\n' 'usage: sh conformance/run.sh [--lean]' >&2; exit 2 ;;
esac
ocaml_compiler=${OCAMLC:-ocamlc}
lean_executable=${LEAN:-lean}
command -v "$ocaml_compiler" >/dev/null 2>&1 || {
  printf '%s\n' 'Missing OCaml compiler. Set OCAMLC to OCaml 5.5.1 ocamlc.' >&2
  exit 127
}
ocaml_compiler=$(command -v "$ocaml_compiler")
case "$ocaml_compiler" in /*) ;; *) ocaml_compiler="$(pwd)/$ocaml_compiler" ;; esac
test "$("$ocaml_compiler" -version)" = "$(cat .ocaml-version)" || {
  printf '%s\n' 'OCaml compiler version differs from .ocaml-version.' >&2
  exit 2
}
if "$regenerate"; then
  command -v "$lean_executable" >/dev/null 2>&1 || {
    printf '%s\n' 'Missing Lean oracle toolchain. Set LEAN to Lean 4.34.1.' >&2
    exit 127
  }
  lean_executable=$(command -v "$lean_executable")
  case "$lean_executable" in /*) ;; *) lean_executable="$(pwd)/$lean_executable" ;; esac
  # Lean's runtime importer starts a child named lean; select the same toolchain.
  PATH="$(dirname "$lean_executable"):$PATH"
  export PATH
  lean_identity=$("$lean_executable" --version)
  case "$lean_identity" in
    'Lean (version 4.34.1,'*'commit 5045d0056413266e57c625dcd7c365b10e377c52,'*) ;;
    *) printf '%s\n' 'Lean version or commit differs from the pinned oracle.' >&2; exit 2 ;;
  esac
fi
python3 tools/test_acceptance.py
python3 tools/check_provenance.py
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cp reference/conversion.ml reference/conversion.mli conformance/replay.ml \
  reference/bounded_parallel.ml reference/bounded_parallel.mli \
  reference/definition_batch.ml reference/definition_batch.mli \
  conformance/rust_replay.ml conformance/adversarial.ml conformance/batch.ml \
  conformance/pool_start_failure.ml "$build/"
(
  cd "$build"
  "$ocaml_compiler" -c conversion.mli
  "$ocaml_compiler" -c conversion.ml
  "$ocaml_compiler" -c bounded_parallel.mli
  "$ocaml_compiler" -c bounded_parallel.ml
  "$ocaml_compiler" -c definition_batch.mli
  "$ocaml_compiler" -c definition_batch.ml
  "$ocaml_compiler" -o replay conversion.cmo replay.ml
  "$ocaml_compiler" -o rust_replay conversion.cmo rust_replay.ml
  "$ocaml_compiler" -o adversarial conversion.cmo adversarial.ml
  "$ocaml_compiler" -I +unix -o batch unix.cma conversion.cmo bounded_parallel.cmo \
    definition_batch.cmo batch.ml
  "$ocaml_compiler" -I +unix -o pool_start_failure unix.cma bounded_parallel.cmo \
    pool_start_failure.ml
)
"$build/replay" conformance/generated.tsv
"$build/rust_replay" conformance/rust-v1.tsv
"$build/adversarial"
"$build/batch"
"$build/pool_start_failure"
if "$regenerate"; then
  "$lean_executable" --run oracles/Generate.lean "$build/generated.tsv"
  diff -u conformance/generated.tsv "$build/generated.tsv"
  diff -u conformance/generated.tsv.types "$build/generated.tsv.types"
  diff -u conformance/generated.tsv.defs "$build/generated.tsv.defs"
  "$lean_executable" --run oracles/ValidateTypingRefusals.lean conformance/generated.tsv.types
  "$lean_executable" --run oracles/ValidateDefinitionRefusals.lean conformance/generated.tsv.defs
  "$lean_executable" --run oracles/RustBaseline.lean "$build/rust-v1.tsv"
  diff -u conformance/rust-v1.tsv "$build/rust-v1.tsv"
  printf '%s\n' 'Pinned Lean regeneration passed: all four fixture files match byte for byte'
fi
