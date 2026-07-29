#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

if [[ ! -f "$SRC/Accounts/PublishedTripClient.swift" ]]; then
  echo "✗ PublishedTripClient eksik; trip kapsamlı yayın henüz uygulanmadı" >&2
  exit 1
fi

if rg -n 'livePostSecret|LIVE_POST_SECRET|x-live-secret' "$SRC"; then
  echo "✗ Eski paylaşılmış yayın kimlik bilgisi kaldırılmadı" >&2
  exit 1
fi

swiftc -O -o "$OUT/publishedtripcheck" \
  "$DIR/published-trip-check.swift" \
  "$SRC/Models.swift" \
  "$SRC/RouteStepPolicy.swift" \
  "$SRC/ArrivalTarget.swift" \
  "$SRC/Accounts/AccountModels.swift" \
  "$SRC/Config.swift" \
  "$SRC/Accounts/KeychainTokenStore.swift" \
  "$SRC/Accounts/BearerSessionCoordinator.swift" \
  "$SRC/Accounts/PublishedTripClient.swift" \
  "$SRC/PublishOutbox.swift"
"$OUT/publishedtripcheck"
