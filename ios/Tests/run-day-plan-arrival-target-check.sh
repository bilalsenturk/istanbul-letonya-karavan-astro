#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

cp "$DIR/day-plan-arrival-target-check.swift" "$OUT/main.swift"
swiftc -O -o "$OUT/day-plan-arrival-target-check" \
  "$OUT/main.swift" \
  "$SRC/Models.swift" \
  "$SRC/ArrivalTarget.swift" \
  "$SRC/Accounts/AccountModels.swift" \
  "$SRC/TripPlanner.swift" \
  "$SRC/RouteStepPolicy.swift" \
  "$SRC/RouteAnnouncementPolicy.swift"
"$OUT/day-plan-arrival-target-check"
