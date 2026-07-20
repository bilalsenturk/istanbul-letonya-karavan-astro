#!/usr/bin/env bash
# Kuzey → TestFlight. Tek komutla yeni sürüm: derle, imzala, yükle.
# Yükleme bitince Apple ~15 dk işler, sonra iç testçilerin telefonuna düşer.
#
# Gerekli:
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   ASC_KEY_ID ve ASC_ISSUER_ID (aşağıdaki varsayılanlar ya da ortam değişkeni)
set -euo pipefail

KEY_ID="${ASC_KEY_ID:-8UAZ5US552}"
ISSUER="${ASC_ISSUER_ID:-851d9c47-e440-45ca-b431-67aa0fc12079}"
IOS_DIR="$(cd "$(dirname "$0")/../ios" && pwd)"
ARCHIVE="/tmp/Kuzey-tf.xcarchive"
EXPORT_DIR="/tmp/Kuzey-tf-export"

cd "$IOS_DIR"

# Her yüklemede build numarası artmalı — Apple aynı numarayı ikinci kez kabul etmez.
CURRENT=$(grep -m1 "CURRENT_PROJECT_VERSION:" project.yml | tr -dc '0-9')
NEXT=$((CURRENT + 1))
echo "▸ build numarası: $CURRENT → $NEXT"
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CURRENT\"/CURRENT_PROJECT_VERSION: \"$NEXT\"/g" project.yml

echo "▸ proje üretiliyor"
xcodegen generate >/dev/null

echo "▸ arşivleniyor (Release)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -destination 'generic/platform=iOS' -configuration Release \
  -allowProvisioningUpdates archive -archivePath "$ARCHIVE" \
  | grep -E "error:|ARCHIVE" || true

echo "▸ dışa aktarılıyor"
cat > /tmp/kuzey-tf-export.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>teamID</key><string>YQUGG5VXCC</string>
<key>signingStyle</key><string>automatic</string>
<key>uploadSymbols</key><true/>
<key>destination</key><string>export</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist /tmp/kuzey-tf-export.plist -allowProvisioningUpdates \
  | grep -E "error|EXPORT" || true

echo "▸ Apple'a yükleniyor"
xcrun altool --upload-app -f "$EXPORT_DIR/Kuzey.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER" | tail -5

echo "✓ yüklendi (build $NEXT). Apple ~15 dk işler, sonra TestFlight'ta görünür."
