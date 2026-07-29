#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
release_script="$root/tools/testflight.sh"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '  ✓ %s\n' "$1"
}

printf '\n=== Release betiği güvenlik sözleşmesi ===\n'
bash -n "$release_script" || fail "testflight.sh kabuk sözdizimi geçersiz"
grep -Fxq 'set -euo pipefail' "$release_script" || fail "testflight.sh set -euo pipefail kullanmalı"
if grep -Eq '\|\|[[:space:]]*true' "$release_script"; then
  fail "testflight.sh hata yutan || true kullanmamalı"
fi
grep -Fq 'CURRENT_PROJECT_VERSION="$NEXT"' "$release_script" \
  || fail "arşiv komutu bir sonraki build'i yalnızca komut satırında geçmeli"
pass "katı kabuk, hata yayılımı ve build override sözleşmesi"

make_fixture() {
  local name="$1"
  local fixture="$out/$name"
  mkdir -p "$fixture/tools" "$fixture/ios/Kuzey.xcodeproj" "$fixture/public" "$fixture/bin"
  cp "$release_script" "$fixture/tools/testflight.sh"
  cp "$root/tools/check-ios-release-version.mjs" "$fixture/tools/check-ios-release-version.mjs"
  cp "$root/ios/project.yml" "$fixture/ios/project.yml"
  cp "$root/ios/Kuzey.xcodeproj/project.pbxproj" "$fixture/ios/Kuzey.xcodeproj/project.pbxproj"
  cp "$root/public/kuzey-version.json" "$fixture/public/kuzey-version.json"

  node --input-type=module - "$fixture/public/kuzey-version.json" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
const path = process.argv[2];
const manifest = JSON.parse(readFileSync(path, "utf8"));
writeFileSync(path, `${JSON.stringify({ latestBuild: 17, minBuild: manifest.minBuild }, null, 2)}\n`);
NODE

  cat > "$fixture/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

stage=archive
archive_path=""
export_path=""
has_next=false
while (($#)); do
  case "$1" in
    -exportArchive) stage=export; shift ;;
    -archivePath) archive_path="$2"; shift 2 ;;
    -exportPath) export_path="$2"; shift 2 ;;
    CURRENT_PROJECT_VERSION=18) has_next=true; shift ;;
    *) shift ;;
  esac
done

if [[ "$stage" == archive && "$has_next" != true ]]; then
  printf 'archive CURRENT_PROJECT_VERSION=18 almadı\n' >&2
  exit 64
fi
if [[ "${FAKE_FAIL_STAGE:-}" == "$stage" ]]; then
  printf '%s failure\n' "$stage" >&2
  exit 65
fi
if [[ "$stage" == archive ]]; then
  mkdir -p "$archive_path"
  printf 'ARCHIVE SUCCEEDED\n'
else
  mkdir -p "$export_path"
  : > "$export_path/Kuzey.ipa"
  printf 'EXPORT SUCCEEDED\n'
fi
SH

  cat > "$fixture/bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

root="${RELEASE_FIXTURE_ROOT:?}"
yaml_values="$(grep 'CURRENT_PROJECT_VERSION:' "$root/ios/project.yml" | tr -dc '0-9\n' | sort -u | tr '\n' ' ')"
manifest_value="$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).latestBuild" "$root/public/kuzey-version.json")"
if [[ "$yaml_values" != "17 " || "$manifest_value" != "17" ]]; then
  printf 'kaynaklar yüklemeden önce değişti: yaml=%s manifest=%s\n' "$yaml_values" "$manifest_value" >&2
  exit 66
fi
printf 'upload kaynak build 17 gördü\n' >> "${RELEASE_TEST_LOG:?}"
if [[ "${FAKE_FAIL_STAGE:-}" == upload ]]; then
  printf 'upload failure\n' >&2
  exit 67
fi
printf 'UPLOAD SUCCEEDED\n'
SH

  cat > "$fixture/bin/xcodegen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

root="${RELEASE_FIXTURE_ROOT:?}"
yaml_values="$(grep 'CURRENT_PROJECT_VERSION:' "$root/ios/project.yml" | tr -dc '0-9\n' | sort -u | tr '\n' ' ')"
manifest_value="$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).latestBuild" "$root/public/kuzey-version.json")"
if [[ "$yaml_values" != "18 " || "$manifest_value" != "18" ]]; then
  printf 'xcodegen kaynak kaydı tamamlanmadan çağrıldı\n' >&2
  exit 68
fi
perl -0pi -e 's/CURRENT_PROJECT_VERSION = 17;/CURRENT_PROJECT_VERSION = 18;/g' \
  "$root/ios/Kuzey.xcodeproj/project.pbxproj"
SH

  chmod +x "$fixture/tools/testflight.sh" "$fixture/bin/xcodebuild" "$fixture/bin/xcrun" "$fixture/bin/xcodegen"
  printf '%s\n' "$fixture"
}

assert_build() {
  local fixture="$1"
  local expected="$2"
  local output
  output="$(node "$fixture/tools/check-ios-release-version.mjs" 2>&1)" \
    || fail "fixture build $expected değerinde tutarlı değil: $output"
  grep -Fq "build $expected" <<<"$output" || fail "fixture checker build $expected raporlamadı"
}

run_failure_case() {
  local stage="$1"
  local fixture
  fixture="$(make_fixture "fail-$stage")"
  local log="$fixture/release.log"
  : > "$log"

  if PATH="$fixture/bin:$PATH" \
    RELEASE_FIXTURE_ROOT="$fixture" RELEASE_TEST_LOG="$log" FAKE_FAIL_STAGE="$stage" \
    ASC_KEY_ID="test-key" ASC_ISSUER_ID="test-issuer" \
    bash "$fixture/tools/testflight.sh" >"$fixture/output.log" 2>&1; then
    fail "$stage hatası release komutundan yayılmadı"
  fi
  assert_build "$fixture" 17
  pass "$stage hatası kaynak build'i değiştirmeden yayıldı"
}

run_failure_case archive
run_failure_case export
run_failure_case upload

printf '\n=== Sürüm kaynağı kapsamı ===\n'
missing_config_fixture="$(make_fixture missing-project-config)"
perl -0pi -e 's/^\s*CURRENT_PROJECT_VERSION = 17;\n//m' \
  "$missing_config_fixture/ios/Kuzey.xcodeproj/project.pbxproj"
if node "$missing_config_fixture/tools/check-ios-release-version.mjs" \
  >"$missing_config_fixture/checker.log" 2>&1; then
  fail "sürüm kontrolü eksik pbx build ayarını kabul etti"
fi
pass "sürüm kontrolü app/widget yapılandırmalarından eksik build ayarını reddetti"

printf '\n=== Başarılı yükleme sırası ===\n'
success_fixture="$(make_fixture success)"
success_log="$success_fixture/release.log"
: > "$success_log"
PATH="$success_fixture/bin:$PATH" \
  RELEASE_FIXTURE_ROOT="$success_fixture" RELEASE_TEST_LOG="$success_log" \
  ASC_KEY_ID="test-key" ASC_ISSUER_ID="test-issuer" \
  bash "$success_fixture/tools/testflight.sh" >"$success_fixture/output.log" 2>&1 \
  || fail "başarılı kontrollü yükleme tamamlanmadı: $(<"$success_fixture/output.log")"

grep -Fxq 'upload kaynak build 17 gördü' "$success_log" \
  || fail "yükleme kaynakların hâlâ build 17 olduğunu gözlemlemedi"
assert_build "$success_fixture" 18
if grep -Fq 'XXXXXX' "$success_fixture/public/kuzey-version.json"; then
  fail "başarılı kayıt manifestte yer tutucu URL bıraktı"
fi
pass "yükleme build 17 kaynaklarını kullandı; başarıdan sonra tüm kaynaklar build 18 oldu"

printf '\n✅ RELEASE GÜVENLİĞİ KONTROLLERİ GEÇTİ\n'
