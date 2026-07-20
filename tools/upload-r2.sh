#!/usr/bin/env bash
# Anons seslerini (ve istersen görselleri) Cloudflare R2'ye yükler.
#
# Ön koşullar:
#   1) Cloudflare hesabında bir R2 bucket aç (örn. "kuzey-media")
#   2) Bucket → Settings → Public access → r2.dev alt alan adını AÇ
#      (ya da kendi alan adını bağla). Verdiği adresi not et:
#         https://pub-XXXXXXXX.r2.dev
#   3) wrangler kur:  npm i -g wrangler   ·   giriş:  wrangler login
#
# Kullanım:
#   BUCKET=kuzey-media ./tools/upload-r2.sh          # sesleri yükle
#   BUCKET=kuzey-media WITH_IMAGES=1 ./tools/upload-r2.sh   # görselleri de yükle
#
# Yükleme bitince app tarafında TEK satır değişir (ios/Karavan/Config.swift):
#   static let mediaBaseURL: URL? = URL(string: "https://pub-XXXXXXXX.r2.dev")
set -euo pipefail

BUCKET="${BUCKET:-kuzey-media}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v wrangler >/dev/null || { echo "wrangler yok:  npm i -g wrangler"; exit 1; }

upload_dir() {
  local src="$1" prefix="$2" count=0
  [ -d "$src" ] || { echo "atlandı (yok): $src"; return; }
  while IFS= read -r -d '' f; do
    local rel="${f#"$src"/}"
    wrangler r2 object put "$BUCKET/$prefix/$rel" --file "$f" --remote >/dev/null
    count=$((count + 1))
    printf "\r  %s: %d dosya" "$prefix" "$count"
  done < <(find "$src" -type f ! -name '.DS_Store' -print0)
  printf "\r  %s: %d dosya ✓\n" "$prefix" "$count"
}

echo "R2 bucket: $BUCKET"
upload_dir "$ROOT/public/audio" "audio"

if [ "${WITH_IMAGES:-0}" = "1" ]; then
  upload_dir "$ROOT/public/assets/gallery" "assets/gallery"
  upload_dir "$ROOT/public/assets/camps" "assets/camps"
fi

cat <<'EOF'

Bitti. Son adım — app'te medya adresini işaretle:

  ios/Karavan/Config.swift
    static let mediaBaseURL: URL? = URL(string: "https://pub-XXXXXXXX.r2.dev")

Doğrulama:
  curl -I https://pub-XXXXXXXX.r2.dev/audio/manifest.json     # 200 dönmeli
EOF
