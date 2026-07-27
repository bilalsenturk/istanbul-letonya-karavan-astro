#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
INPUTS=("$DIR/travel-content-check.swift")
if [[ -f "$SRC/TravelContent.swift" ]]; then
  INPUTS+=("$SRC/TravelContent.swift")
fi
swiftc -parse-as-library -O -o "$OUT/travel-content-check" "${INPUTS[@]}"
"$OUT/travel-content-check"
