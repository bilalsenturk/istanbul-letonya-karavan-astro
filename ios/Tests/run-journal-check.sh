#!/usr/bin/env bash
# Günlük kuyruğu doğrulaması (UI'sız, saniyeler içinde).
#   ./ios/Tests/run-journal-check.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
# swiftc yalnızca tam olarak "main.swift" adlı dosyada üst düzey kod kabul
# eder (birden çok dosya birlikte derlenirken). Kaynak dosya adını
# değiştirmemek için geçici derleme dizininde bir kopya kullanıyoruz.
cp "$DIR/journal-queue-check.swift" "$OUT/main.swift"
swiftc -O -o "$OUT/journalcheck" \
  "$OUT/main.swift" \
  "$SRC/Journal/JournalEntry.swift" \
  "$SRC/Journal/JournalQueue.swift"
"$OUT/journalcheck"
