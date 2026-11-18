#!/bin/sh
# Compare current bytecode with hash-verified reference sources from merged main.
set -eu
cd "$(dirname "$0")/.."
ocaml_compiler=${OCAMLC:-ocamlc}
command -v "$ocaml_compiler" >/dev/null 2>&1 || {
  printf '%s\n' 'Missing OCaml compiler. Set OCAMLC to OCaml 5.5.1 ocamlc.' >&2
  exit 127
}
ocaml_compiler=$(command -v "$ocaml_compiler")
case "$ocaml_compiler" in /*) ;; *) ocaml_compiler="$(pwd)/$ocaml_compiler" ;; esac
test "$("$ocaml_compiler" -version)" = "$(cat .ocaml-version)"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
baseline=d2e2bdf63a49b75ba2091132613fcf88b76a183e
for module in conversion bounded_parallel definition_batch; do
  for suffix in ml mli; do
    source="reference/$module.$suffix"
    if test -n "${OPTIMIZATION_BASELINE:-}"; then
      cp "$OPTIMIZATION_BASELINE/$source" "$build/old_$module.$suffix"
    else
      git show "$baseline:$source" > "$build/old_$module.$suffix" || {
        printf '%s\n' 'Pinned baseline unavailable. Use full Git history or OPTIMIZATION_BASELINE with the verified reference sources.' >&2
        exit 2
      }
    fi
    cp "$source" "$build/$module.$suffix"
  done
done
(
  cd "$build"
  sha256sum -c <<'HASHES'
b61132c18c0b8db34e8623547632249e2bed257a53f1b6e5385b076f2aaad956  old_conversion.ml
34a3664e669fd3323583640fb2ea58b529a76e3dc820c08e116330322d00acec  old_conversion.mli
5f0cb96226bd0878cd6347e681e3affdf2e1991ef092c9b7379f031ba82aea41  old_definition_batch.ml
6465b2f6c6de50bd3471af2d1cb9e8227d0e3b92334dd66a45063d789ff34224  old_definition_batch.mli
6f686225a0bd448e6ab3241622efc6cdc763315bd7bb65fdb5f0ce9f9ee84072  old_bounded_parallel.ml
3eb129db11693eec996f19a7030313673d046bc4e7b802e92da6faed003667c4  old_bounded_parallel.mli
HASHES
)
cp conformance/optimization.ml "$build/"
(
  cd "$build"
  for suffix in ml mli; do
    sed -i 's/Conversion/Old_conversion/g; s/Bounded_parallel/Old_bounded_parallel/g' "old_definition_batch.$suffix"
  done
  for module in old_conversion old_bounded_parallel old_definition_batch conversion bounded_parallel definition_batch; do
    "$ocaml_compiler" -c "$module.mli"
    "$ocaml_compiler" -c "$module.ml"
  done
  "$ocaml_compiler" -o optimization old_conversion.cmo old_bounded_parallel.cmo \
    old_definition_batch.cmo conversion.cmo bounded_parallel.cmo definition_batch.cmo optimization.ml
)
"$build/optimization"
