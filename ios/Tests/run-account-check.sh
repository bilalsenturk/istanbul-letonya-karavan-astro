#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/accountcheck" \
  "$DIR/account-domain-check.swift" \
  "$SRC/ArrivalTarget.swift" \
  "$SRC/Accounts/AccountModels.swift" \
  "$SRC/Routes/RouteDraft.swift"
"$OUT/accountcheck"
