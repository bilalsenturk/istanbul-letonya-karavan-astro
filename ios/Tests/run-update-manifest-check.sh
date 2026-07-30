#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -parse-as-library -O -o "$OUT/update-manifest-check" \
  "$DIR/update-manifest-check.swift" \
  "$SRC/UpdateManifest.swift"
"$OUT/update-manifest-check"
