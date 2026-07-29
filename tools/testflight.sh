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

# Kaynakların tek bir build'de olduğunu doğrula ve yalnızca o değerden ilerle.
node "$VERSION_CHECK"
CURRENT=$(grep -m1 "CURRENT_PROJECT_VERSION:" project.yml \
  | sed -E 's/.*CURRENT_PROJECT_VERSION:[^0-9]*([0-9]+).*/\1/')
NEXT=$((CURRENT + 1))
TRANSACTION_DIR="${KUZ_RELEASE_TRANSACTION_DIR:-/tmp/kuzey-tf-version-$NEXT}"
STAGED_ROOT="$TRANSACTION_DIR/staged"
ORIGINAL_ROOT="$TRANSACTION_DIR/original"
ACCEPTED_MARKER="$TRANSACTION_DIR/upload-accepted"

case "$TRANSACTION_DIR" in
  ""|/|/tmp|"$ROOT_DIR"|"$IOS_DIR")
    printf '❌ güvenli olmayan release transaction yolu: %s\n' "$TRANSACTION_DIR" >&2
    exit 2
    ;;
esac
case "$TRANSACTION_DIR/" in
  "$IOS_DIR/"*)
    printf '❌ release transaction yolu iOS kaynak ağacının içinde olamaz: %s\n' "$TRANSACTION_DIR" >&2
    exit 2
    ;;
esac

ROLLBACK_ACTIVE=false

finish_release() {
  local exit_code=$?
  trap - EXIT
  if [[ "$ROLLBACK_ACTIVE" == true ]]; then
    set +e
    cp "$ORIGINAL_ROOT/project.yml" "$IOS_DIR/project.yml"
    restore_yaml=$?
    cp "$ORIGINAL_ROOT/project.pbxproj" "$IOS_DIR/Kuzey.xcodeproj/project.pbxproj"
    restore_project=$?
    cp "$ORIGINAL_ROOT/kuzey-version.json" "$MANIFEST"
    restore_manifest=$?
    rm -f "$IOS_DIR/project.yml.kuzey-release-pending"
    rm -f "$IOS_DIR/Kuzey.xcodeproj/project.pbxproj.kuzey-release-pending"
    rm -f "$MANIFEST.kuzey-release-pending"
    set -e
    if ((restore_yaml != 0 || restore_project != 0 || restore_manifest != 0)); then
      printf '❌ release kaydı geri alınamadı; transaction alanını koruyun: %s\n' "$TRANSACTION_DIR" >&2
      exit 74
    fi
    printf '⚠️ kaynak sürümleri geri alındı; kabul edilen build %s transaction alanından kurtarılabilir: %s\n' \
      "$NEXT" "$TRANSACTION_DIR" >&2
  fi
  exit "$exit_code"
}
trap finish_release EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

update_staged_versions() {
  node --input-type=module - \
    "$STAGED_ROOT/ios/project.yml" "$STAGED_ROOT/public/kuzey-version.json" "$CURRENT" "$NEXT" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";

const [, , projectPath, manifestPath, current, next] = process.argv;
const project = readFileSync(projectPath, "utf8");
const versionPattern = /^([ \t]*CURRENT_PROJECT_VERSION:[ \t]*)(["']?)(\d+)\2([ \t]*(?:#.*)?)$/gm;
const matches = [...project.matchAll(versionPattern)];
if (matches.length !== 2 || matches.some((match) => match[3] !== current)) {
  throw new Error("project.yml build değerleri beklenen kaynak sürümünde değil");
}

const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
if (String(manifest.latestBuild) !== current) {
  throw new Error("manifest build değeri beklenen kaynak sürümünde değil");
}

const updatedProject = project.replace(
  versionPattern,
  (_match, prefix, _quote, _value, suffix) => `${prefix}"${next}"${suffix}`,
);
const updatedManifest = { ...manifest, latestBuild: Number(next) };
writeFileSync(projectPath, updatedProject);
writeFileSync(manifestPath, `${JSON.stringify(updatedManifest, null, 2)}\n`);
NODE
}

prepare_transaction() {
  if [[ -e "$TRANSACTION_DIR" ]]; then
    rm -rf "$TRANSACTION_DIR"
  fi
  mkdir -p "$STAGED_ROOT" "$ORIGINAL_ROOT" "$STAGED_ROOT/tools" "$STAGED_ROOT/public"
  cp -R "$IOS_DIR" "$STAGED_ROOT/ios"
  cp "$VERSION_CHECK" "$STAGED_ROOT/tools/check-ios-release-version.mjs"
  cp "$MANIFEST" "$STAGED_ROOT/public/kuzey-version.json"
  cp "$IOS_DIR/project.yml" "$ORIGINAL_ROOT/project.yml"
  cp "$IOS_DIR/Kuzey.xcodeproj/project.pbxproj" "$ORIGINAL_ROOT/project.pbxproj"
  cp "$MANIFEST" "$ORIGINAL_ROOT/kuzey-version.json"

  update_staged_versions
  (cd "$STAGED_ROOT/ios" && xcodegen generate >/dev/null)
  node "$STAGED_ROOT/tools/check-ios-release-version.mjs"
}

install_file() {
  local staged="$1"
  local destination="$2"
  local pending="${destination}.kuzey-release-pending"
  cp "$staged" "$pending"
  mv "$pending" "$destination"
}

commit_staged_versions() {
  node "$STAGED_ROOT/tools/check-ios-release-version.mjs"
  ROLLBACK_ACTIVE=true
  install_file "$STAGED_ROOT/ios/project.yml" "$IOS_DIR/project.yml"
  install_file "$STAGED_ROOT/ios/Kuzey.xcodeproj/project.pbxproj" "$IOS_DIR/Kuzey.xcodeproj/project.pbxproj"
  install_file "$STAGED_ROOT/public/kuzey-version.json" "$MANIFEST"
  node "$VERSION_CHECK"
  ROLLBACK_ACTIVE=false
  rm -rf "$TRANSACTION_DIR"
}

echo "▸ build numarası: $CURRENT → $NEXT"

if [[ -f "$ACCEPTED_MARKER" ]]; then
  accepted_build="$(<"$ACCEPTED_MARKER")"
  if [[ "$accepted_build" != "$NEXT" ]]; then
    printf '❌ recovery build değeri beklenmiyor: %s (beklenen %s)\n' "$accepted_build" "$NEXT" >&2
    exit 3
  fi
  echo "▸ Apple'ın kabul ettiği build $NEXT kaynaklara kaydediliyor"
  commit_staged_versions
  echo "✓ build $NEXT kaydı kurtarıldı; yeniden yükleme yapılmadı."
  exit 0
fi

# XcodeGen ve sürüm kontrolünü izole kopyada yüklemeden önce tamamla. Gerçek
# kaynaklar Apple kabul edene kadar CURRENT değerinde kalır.
prepare_transaction

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
printf '%s\n' "$NEXT" > "$ACCEPTED_MARKER"

echo "▸ doğrulanmış kaynak sürümü kaydediliyor"
commit_staged_versions

echo "✓ yüklendi (build $NEXT). Apple ~15 dk işler, sonra TestFlight'ta görünür."
