#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/bearersessioncheck" \
  "$DIR/bearer-session-check.swift" \
  "$SRC/Config.swift" \
  "$SRC/Accounts/KeychainTokenStore.swift" \
  "$SRC/Accounts/BearerSessionCoordinator.swift"
"$OUT/bearersessioncheck"
