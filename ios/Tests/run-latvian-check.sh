#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan/Learning"
OUT="$(mktemp -d)"
swiftc -O -parse-as-library -o "$OUT/latviancheck" \
  "$DIR/latvian-engine-check.swift" \
  "$SRC/LatvianPack.swift"
"$OUT/latviancheck"
