#!/bin/sh
# Keep fetched compiler sources and products outside the governed repository.
set -eu
if [ "$#" -ne 1 ]; then
  printf '%s\n' 'usage: sh tools/build_goose.sh /absolute/path/to/new-goose-checkout' >&2
  exit 2
fi
case "$1" in /*) ;; *) printf '%s\n' 'destination must be absolute' >&2; exit 2 ;; esac
cd "$(dirname "$0")/.."
goose_destination=$1
goose_revision=$(python3 -c 'import json; print(json.load(open("conformance/goose-toolchain.json"))["revision"])')
test ! -e "$goose_destination" || {
  printf '%s\n' 'destination already exists; use GOOSE_SOURCE for an existing pinned checkout' >&2
  exit 2
}
git clone --no-checkout https://github.com/aardappel/goose.git "$goose_destination"
git -C "$goose_destination" checkout --detach "$goose_revision"
test "$(git -C "$goose_destination" rev-parse HEAD)" = "$goose_revision"
cmake -S "$goose_destination" -B "$goose_destination/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$goose_destination/build" -j2
printf 'GOOSE_SOURCE=%s\n' "$goose_destination"
