#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
INPUTS=("$DIR/travel-content-store-check.swift" "$SRC/TravelContent.swift")
if [[ -f "$SRC/TravelContentStore.swift" ]]; then
  INPUTS+=("$SRC/TravelContentStore.swift")
fi
swiftc -parse-as-library -O -o "$OUT/travel-content-store-check" "${INPUTS[@]}"
cmp "$DIR/../../public/assets/travel-content.json" "$SRC/Resources/travel-content.json"
"$OUT/travel-content-store-check" "$SRC/Resources/travel-content.json"
