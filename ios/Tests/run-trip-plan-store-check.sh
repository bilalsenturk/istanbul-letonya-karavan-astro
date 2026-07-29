#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$OUT" "$TEST_HOME"' EXIT

swiftc -O -o "$OUT/trip-plan-store-check" \
  "$DIR/trip-plan-store-check.swift" \
  "$SRC/Models.swift" \
  "$SRC/ArrivalTarget.swift" \
  "$SRC/Accounts/AccountModels.swift" \
  "$SRC/Accounts/PublishedTripClient.swift" \
  "$SRC/TripPlanner.swift" \
  "$SRC/RouteStepPolicy.swift" \
  "$SRC/TripPlanStore.swift"

CFFIXED_USER_HOME="$TEST_HOME" "$OUT/trip-plan-store-check"
