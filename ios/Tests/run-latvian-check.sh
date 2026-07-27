#!/usr/bin/env bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan/Learning"
OUT="$(mktemp -d)"
# -O şart: performans bütçeleri sürüm derlemesine göre ölçülüyor.
swiftc -O -parse-as-library -o "$OUT/latviancheck" \
  "$DIR/latvian-engine-check.swift" \
  "$SRC/LatvianPack.swift" \
  "$SRC/LatvianExercise.swift" \
  "$SRC/LatvianGrader.swift" \
  "$SRC/LatvianMemory.swift" \
  "$SRC/LatvianExerciseFactory.swift" \
  "$SRC/LatvianProgress.swift" \
  "$SRC/LatvianLessonBuilder.swift"
"$OUT/latviancheck"

# Süreçler arası belirlenimcilik.
# Swift hash tohumunu her süreçte yeniden üretir, dolayısıyla `Set` sırasına sızan bir
# belirsizlik aynı süreç içinde iki kez çağırmakla yakalanamaz — yaşanan hata tam olarak
# buydu. Aynı özet üç ayrı süreçte de aynı çıkmak zorunda.
echo ""
echo "=== Süreçler arası belirlenimcilik ==="
FP1="$("$OUT/latviancheck" --fingerprint)"
FP2="$("$OUT/latviancheck" --fingerprint)"
FP3="$("$OUT/latviancheck" --fingerprint)"
echo "  1: $FP1"
echo "  2: $FP2"
echo "  3: $FP3"
if [ "$FP1" != "$FP2" ] || [ "$FP1" != "$FP3" ]; then
  echo "  ✗ üç ayrı süreç aynı soruları üretmedi" >&2
  echo "" >&2
  echo "1 kontrol başarısız." >&2
  exit 1
fi
echo "  ✓ üç ayrı süreç aynı soruları üretti"
echo ""
echo "Tüm Letonca motor kontrolleri geçti."
