#!/usr/bin/env bash
# Kuzey → TestFlight. Tek komutla yeni sürüm: derle, imzala, yükle.
# Yükleme bitince Apple ~15 dk işler, sonra iç testçilerin telefonuna düşer.
#
# Gerekli:
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   ASC_KEY_ID ve ASC_ISSUER_ID (aşağıdaki varsayılanlar ya da ortam değişkeni)
set -euo pipefail
umask 077

KEY_ID="${ASC_KEY_ID:-8UAZ5US552}"
ISSUER="${ASC_ISSUER_ID:-851d9c47-e440-45ca-b431-67aa0fc12079}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IOS_DIR="$ROOT_DIR/ios"
MANIFEST="$ROOT_DIR/public/kuzey-version.json"
VERSION_CHECK="$ROOT_DIR/tools/check-ios-release-version.mjs"

cd "$IOS_DIR"

# Kaynakların tek bir build'de olduğunu doğrula ve yalnızca o değerden ilerle.
node "$VERSION_CHECK"
CURRENT=$(grep -m1 "CURRENT_PROJECT_VERSION:" project.yml \
  | sed -E 's/.*CURRENT_PROJECT_VERSION:[^0-9]*([0-9]+).*/\1/')
NEXT=$((CURRENT + 1))

SYSTEM_TEMP_ROOT="$(realpath /tmp)"
ROOT_DIR_CANONICAL="$(realpath "$ROOT_DIR")"
ROOT_KEY="$(printf '%s' "$ROOT_DIR_CANONICAL" | shasum -a 256 | awk '{print substr($1, 1, 16)}')"
OWNED_ROOT_REQUEST="${KUZ_RELEASE_OWNED_ROOT:-/tmp/kuzey-testflight-release-$(id -u)-$ROOT_KEY}"
ROOT_SENTINEL_VALUE="kuzey-testflight-release:v1:$ROOT_KEY"
TRANSACTION_SENTINEL_VALUE="kuzey-testflight-transaction:v1:$ROOT_KEY:$NEXT"

canonical_candidate() {
  local requested="$1"
  if [[ -e "$requested" || -L "$requested" ]]; then
    realpath "$requested"
    return
  fi

  local parent name canonical_parent
  parent="$(dirname "$requested")"
  name="$(basename "$requested")"
  if [[ ! -d "$parent" ]]; then
    printf '❌ release yolu için güvenilir üst dizin yok: %s\n' "$requested" >&2
    return 1
  fi
  canonical_parent="$(realpath "$parent")"
  printf '%s/%s\n' "$canonical_parent" "$name"
}

owned_root_name="$(basename "$OWNED_ROOT_REQUEST")"
case "$owned_root_name" in
  kuzey-testflight-release-*) ;;
  *)
    printf '❌ release-owned kök adı geçersiz: %s\n' "$OWNED_ROOT_REQUEST" >&2
    exit 2
    ;;
esac

OWNED_ROOT="$(canonical_candidate "$OWNED_ROOT_REQUEST")"
case "$OWNED_ROOT/" in
  "$SYSTEM_TEMP_ROOT/"*) ;;
  *)
    printf '❌ release-owned kök sistem geçici dizininin içinde olmalı: %s\n' "$OWNED_ROOT" >&2
    exit 2
    ;;
esac

ROOT_SENTINEL="$OWNED_ROOT/.kuzey-testflight-owned"
if [[ -e "$OWNED_ROOT" || -L "$OWNED_ROOT" ]]; then
  if [[ ! -d "$OWNED_ROOT" || -L "$OWNED_ROOT" || ! -O "$OWNED_ROOT" ]]; then
    printf '❌ release-owned kök güvenilir bir kullanıcı dizini değil: %s\n' "$OWNED_ROOT" >&2
    exit 2
  fi
  if [[ ! -f "$ROOT_SENTINEL" || -L "$ROOT_SENTINEL" || ! -O "$ROOT_SENTINEL" \
    || "$(<"$ROOT_SENTINEL")" != "$ROOT_SENTINEL_VALUE" ]]; then
    printf '❌ önceden var olan release-owned kökün sahiplik işareti geçersiz: %s\n' "$OWNED_ROOT" >&2
    exit 2
  fi
else
  mkdir "$OWNED_ROOT"
  printf '%s\n' "$ROOT_SENTINEL_VALUE" > "$ROOT_SENTINEL"
fi

EXPECTED_TRANSACTION_DIR="$OWNED_ROOT/build-$NEXT"
TRANSACTION_REQUEST="${KUZ_RELEASE_TRANSACTION_DIR:-$EXPECTED_TRANSACTION_DIR}"
TRANSACTION_CANONICAL="$(canonical_candidate "$TRANSACTION_REQUEST")"
if [[ "$TRANSACTION_CANONICAL" != "$EXPECTED_TRANSACTION_DIR" ]]; then
  printf '❌ transaction yolu release-owned build alanının dışında: %s\n' "$TRANSACTION_CANONICAL" >&2
  exit 2
fi
TRANSACTION_DIR="$EXPECTED_TRANSACTION_DIR"
TRANSACTION_SENTINEL="$TRANSACTION_DIR/.kuzey-transaction-owned"
STAGED_ROOT="$TRANSACTION_DIR/staged"
ORIGINAL_ROOT="$TRANSACTION_DIR/original"
ACCEPTED_MARKER="$TRANSACTION_DIR/upload-accepted"
ARCHIVE="$TRANSACTION_DIR/Kuzey.xcarchive"
EXPORT_DIR="$TRANSACTION_DIR/export"
EXPORT_PLIST="$TRANSACTION_DIR/ExportOptions.plist"

validate_owned_transaction() {
  local canonical marker_value
  if [[ ! -d "$TRANSACTION_DIR" || -L "$TRANSACTION_DIR" || ! -O "$TRANSACTION_DIR" ]]; then
    printf '❌ transaction güvenilir bir kullanıcı dizini değil: %s\n' "$TRANSACTION_DIR" >&2
    return 1
  fi
  canonical="$(realpath "$TRANSACTION_DIR")"
  case "$canonical/" in
    "$OWNED_ROOT/"*) ;;
    *)
      printf '❌ transaction release-owned kökün dışında: %s\n' "$canonical" >&2
      return 1
      ;;
  esac
  if [[ "$canonical" != "$EXPECTED_TRANSACTION_DIR" ]]; then
    printf '❌ transaction beklenen build alanı değil: %s\n' "$canonical" >&2
    return 1
  fi
  if [[ ! -f "$TRANSACTION_SENTINEL" || -L "$TRANSACTION_SENTINEL" || ! -O "$TRANSACTION_SENTINEL" ]]; then
    printf '❌ transaction sahiplik işareti eksik: %s\n' "$TRANSACTION_DIR" >&2
    return 1
  fi
  marker_value="$(<"$TRANSACTION_SENTINEL")"
  if [[ "$marker_value" != "$TRANSACTION_SENTINEL_VALUE" ]]; then
    printf '❌ transaction sahiplik işareti eşleşmiyor: %s\n' "$TRANSACTION_DIR" >&2
    return 1
  fi
}

remove_owned_transaction() {
  validate_owned_transaction
  rm -rf -- "$TRANSACTION_DIR"
}

if [[ -e "$TRANSACTION_DIR" || -L "$TRANSACTION_DIR" ]]; then
  validate_owned_transaction
fi

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
  if [[ -e "$TRANSACTION_DIR" || -L "$TRANSACTION_DIR" ]]; then
    remove_owned_transaction
  fi
  mkdir "$TRANSACTION_DIR"
  printf '%s\n' "$TRANSACTION_SENTINEL_VALUE" > "$TRANSACTION_SENTINEL"
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
  validate_owned_transaction
  node "$STAGED_ROOT/tools/check-ios-release-version.mjs"
  ROLLBACK_ACTIVE=true
  install_file "$STAGED_ROOT/ios/project.yml" "$IOS_DIR/project.yml"
  install_file "$STAGED_ROOT/ios/Kuzey.xcodeproj/project.pbxproj" "$IOS_DIR/Kuzey.xcodeproj/project.pbxproj"
  install_file "$STAGED_ROOT/public/kuzey-version.json" "$MANIFEST"
  node "$VERSION_CHECK"
  ROLLBACK_ACTIVE=false
  remove_owned_transaction
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
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -destination 'generic/platform=iOS' \
  -configuration Release CURRENT_PROJECT_VERSION="$NEXT" -allowProvisioningUpdates \
  archive -archivePath "$ARCHIVE" 2>&1 | tee "$TRANSACTION_DIR/archive.log"

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
  -exportOptionsPlist "$EXPORT_PLIST" -allowProvisioningUpdates 2>&1 | tee "$TRANSACTION_DIR/export.log"

echo "▸ Apple'a yükleniyor"
xcrun altool --upload-app -f "$EXPORT_DIR/Kuzey.ipa" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER"
printf '%s\n' "$NEXT" > "$ACCEPTED_MARKER"

echo "▸ doğrulanmış kaynak sürümü kaydediliyor"
commit_staged_versions

echo "✓ yüklendi (build $NEXT). Apple ~15 dk işler, sonra TestFlight'ta görünür."
