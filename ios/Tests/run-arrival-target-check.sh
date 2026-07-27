#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/arrival-target-check" \
  "$DIR/arrival-target-check.swift" \
  "$SRC/RouteStepPolicy.swift" \
  "$SRC/ArrivalTarget.swift" \
  "$SRC/Accounts/AccountModels.swift" \
  "$SRC/StayContactProfileStore.swift"
"$OUT/arrival-target-check"
