#!/usr/bin/env bash
# Bildirim kuralları ve disiplini doğrulaması (UI'sız).
#   ./ios/Tests/run-notification-check.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
# swiftc yalnızca tam olarak "main.swift" adlı dosyada üst düzey kod kabul
# eder (birden çok dosya birlikte derlenirken). Kaynak dosya adını
# değiştirmemek için geçici derleme dizininde bir kopya kullanıyoruz.
cp "$DIR/notification-rules-check.swift" "$OUT/main.swift"
swiftc -O -o "$OUT/notifcheck" \
  "$OUT/main.swift" \
  "$SRC/Notifications/NotificationRules.swift" \
  "$SRC/Notifications/NotificationBudget.swift"
"$OUT/notifcheck"
