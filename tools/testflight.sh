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
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
MANIFEST="$ROOT_DIR/public/kuzey-version.json"
VERSION_CHECK="$ROOT_DIR/tools/check-ios-release-version.mjs"
ARCHIVE="/tmp/Kuzey-tf.xcarchive"
EXPORT_DIR="/tmp/Kuzey-tf-export"
EXPORT_PLIST="/tmp/kuzey-tf-export.plist"

cd "$IOS_DIR"

# Her yüklemede build numarası artmalı — Apple aynı numarayı ikinci kez kabul etmez.
node "$VERSION_CHECK"
CURRENT=$(grep -m1 "CURRENT_PROJECT_VERSION:" project.yml | tr -dc '0-9')
NEXT=$((CURRENT + 1))
echo "▸ build numarası: $CURRENT → $NEXT"

echo "▸ arşivleniyor (Release)"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -destination 'generic/platform=iOS' \
  -configuration Release CURRENT_PROJECT_VERSION="$NEXT" -allowProvisioningUpdates \
  archive -archivePath "$ARCHIVE" 2>&1 | tee /tmp/kuzey-archive.log

echo "▸ dışa aktarılıyor"
cat > "$EXPORT_PLIST" <<'PLIST'
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
  -exportOptionsPlist "$EXPORT_PLIST" -allowProvisioningUpdates 2>&1 | tee /tmp/kuzey-export.log

echo "▸ Apple'a yükleniyor"
xcrun altool --upload-app -f "$EXPORT_DIR/Kuzey.ipa" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER"

# Apple yüklemeyi kabul etmeden kaynak sürümlerine dokunma. Böylece arşiv,
# dışa aktarma veya yükleme hatasında repo hâlâ yeniden denenebilir build'de kalır.
node --input-type=module - "$IOS_DIR/project.yml" "$MANIFEST" "$CURRENT" "$NEXT" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";

const [, , projectPath, manifestPath, current, next] = process.argv;
const project = readFileSync(projectPath, "utf8");
const matches = [...project.matchAll(/^\s*CURRENT_PROJECT_VERSION:\s*"?(\d+)"?\s*$/gm)];
if (matches.length !== 2 || matches.some((match) => match[1] !== current)) {
  throw new Error("project.yml build değerleri yükleme sonrasında beklenen kaynak sürümünde değil");
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
if (String(manifest.latestBuild) !== current) {
  throw new Error("manifest build değeri yükleme sonrasında beklenen kaynak sürümünde değil");
}

const updatedProject = project.replace(
  /^(\s*CURRENT_PROJECT_VERSION:\s*)"?\d+"?(\s*)$/gm,
  `$1"${next}"$2`,
);
const updatedManifest = { ...manifest, latestBuild: Number(next) };
writeFileSync(projectPath, updatedProject);
writeFileSync(manifestPath, `${JSON.stringify(updatedManifest, null, 2)}\n`);
NODE

echo "▸ kaynak sürümü kaydediliyor"
xcodegen generate >/dev/null
node "$VERSION_CHECK"

echo "✓ yüklendi (build $NEXT). Apple ~15 dk işler, sonra TestFlight'ta görünür."
