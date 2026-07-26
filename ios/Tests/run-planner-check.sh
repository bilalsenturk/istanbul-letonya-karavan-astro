#!/usr/bin/env bash
# TripPlanner kaskat doğrulaması (UI'sız, saniyeler içinde).
#   ./ios/Tests/run-planner-check.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/plannercheck" \
  "$DIR/main.swift" \
  "$SRC/Models.swift" \
  "$SRC/ArrivalTarget.swift" \
  "$SRC/TripPlanner.swift" \
  "$SRC/RouteStepPolicy.swift" \
  "$SRC/RouteAnnouncementPolicy.swift"
"$OUT/plannercheck"
