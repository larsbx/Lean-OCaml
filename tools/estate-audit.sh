#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
rev=$(python3 -c 'import tomllib; print(next(d["rev"] for d in tomllib.load(open("ESTATE.toml", "rb"))["dep"] if d["id"] == "estate-governance"))')
pin=$(python3 -c 'import tomllib; print(next(d["pin"] for d in tomllib.load(open("ESTATE.toml", "rb"))["dep"] if d["id"] == "estate-governance"))')
printf '%s\n' "$rev" | grep -Eq '^[0-9a-f]{40}$'
audit=$(mktemp)
trap 'rm -f "$audit"' EXIT
if [ "$#" -eq 1 ]; then
  cp "$1" "$audit"
else
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$audit" "https://raw.githubusercontent.com/larsbx/estate-governance/$rev/kernel/audit_estate_layout.py"
fi
printf '%s  %s\n' "${pin#sha256:}" "$audit" | sha256sum --check --strict -
python3 "$audit" --root .
