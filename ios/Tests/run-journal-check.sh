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

# Simulator derlemesinde CloudKit yolu derlenmemeli. `return` sonrasinda
# yalnizca `#endif` kullanmak Swift'in unreachable-code uyarisi vermesine yol
# acar; gercek cihaz kodu ayni kosulun `#else` kolunda kalmali.
awk '
  /#if targetEnvironment\(simulator\)/ { in_simulator = 1; next }
  in_simulator && /#else/ { has_else = 1; next }
  in_simulator && /accountState\(\)/ {
    found_account_state = 1
    if (!has_else) exit 1
  }
  in_simulator && /#endif/ {
    if (!found_account_state) {
      in_simulator = 0
      has_else = 0
    }
  }
  END { if (!found_account_state || !has_else) exit 1 }
' "$SRC/Journal/JournalStore.swift" || {
  echo "  ✗ simulator CloudKit yolu #else ile derlemeden cikarilmamis"
  exit 1
}
echo "  ✓ simulator CloudKit yolu #else ile derlemeden cikariliyor"
