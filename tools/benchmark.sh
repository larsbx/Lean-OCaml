#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ocaml_compiler=${OCAMLC:-ocamlc}
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
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cp reference/conversion.ml reference/conversion.mli \
  reference/bounded_parallel.ml reference/bounded_parallel.mli \
  reference/definition_batch.ml reference/definition_batch.mli \
  conformance/benchmark.ml "$build/"
(
  cd "$build"
  for module in conversion bounded_parallel definition_batch; do
    "$ocaml_compiler" -c "$module.mli"
    "$ocaml_compiler" -c "$module.ml"
  done
  "$ocaml_compiler" -I +unix -o benchmark unix.cma conversion.cmo bounded_parallel.cmo \
    definition_batch.cmo benchmark.ml
)
"$build/benchmark" "$@"
