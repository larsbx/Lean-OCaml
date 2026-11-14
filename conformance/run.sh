#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
cp reference/conversion.ml reference/conversion.mli conformance/replay.ml "$build/"
(
  cd "$build"
  ocamlc -o replay conversion.mli conversion.ml replay.ml
)
"$build/replay" conformance/generated.tsv
if [ "${1:-}" = "--lean" ]; then
  lean --run oracles/Generate.lean "$build/generated.tsv"
  diff -u conformance/generated.tsv "$build/generated.tsv"
  diff -u conformance/generated.tsv.types "$build/generated.tsv.types"
  diff -u conformance/generated.tsv.defs "$build/generated.tsv.defs"
fi
