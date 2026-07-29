#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
release_script="$root/tools/testflight.sh"
real_node="$(command -v node)"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

fail() {
  printf '❌ %s\n' "$1" >&2
  exit 1
}

pass() {
  printf '  ✓ %s\n' "$1"
}

yaml_build() {
  grep -m1 'CURRENT_PROJECT_VERSION:' "$1" | sed -E 's/.*CURRENT_PROJECT_VERSION:[^0-9]*([0-9]+).*/\1/'
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
  local requested_build="${2:-}"
  local fixture="$out/$name"
  mkdir -p "$fixture/tools" "$fixture/ios/Kuzey.xcodeproj" "$fixture/public" "$fixture/bin"
  cp "$release_script" "$fixture/tools/testflight.sh"
  cp "$root/tools/check-ios-release-version.mjs" "$fixture/tools/check-ios-release-version.mjs"
  cp "$root/ios/project.yml" "$fixture/ios/project.yml"
  cp "$root/ios/Kuzey.xcodeproj/project.pbxproj" "$fixture/ios/Kuzey.xcodeproj/project.pbxproj"
  cp "$root/public/kuzey-version.json" "$fixture/public/kuzey-version.json"

  local current
  current="$(yaml_build "$fixture/ios/project.yml")"
  if [[ -n "$requested_build" && "$requested_build" != "$current" ]]; then
    CURRENT="$current" NEXT="$requested_build" node --input-type=module - \
      "$fixture/ios/project.yml" "$fixture/ios/Kuzey.xcodeproj/project.pbxproj" \
      "$fixture/public/kuzey-version.json" <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";
const [, , yamlPath, projectPath, manifestPath] = process.argv;
const current = process.env.CURRENT;
const next = process.env.NEXT;
writeFileSync(yamlPath, readFileSync(yamlPath, "utf8").replace(
  new RegExp(`CURRENT_PROJECT_VERSION: "?${current}"?`, "g"),
  `CURRENT_PROJECT_VERSION: "${next}"`,
));
writeFileSync(projectPath, readFileSync(projectPath, "utf8").replace(
  new RegExp(`CURRENT_PROJECT_VERSION = ${current};`, "g"),
  `CURRENT_PROJECT_VERSION = ${next};`,
));
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
writeFileSync(manifestPath, `${JSON.stringify({ ...manifest, latestBuild: Number(next) }, null, 2)}\n`);
NODE
    current="$requested_build"
  fi

  printf '%s\n' "$current" > "$fixture/expected-current"
  printf '%s\n' "$((current + 1))" > "$fixture/expected-next"

  cat > "$fixture/bin/node" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == */check-ios-release-version.mjs ]]; then
  count=0
  if [[ -f "${RELEASE_NODE_COUNT:?}" ]]; then count="$(<"$RELEASE_NODE_COUNT")"; fi
  count=$((count + 1))
  printf '%s\n' "$count" > "$RELEASE_NODE_COUNT"
  if [[ "${FAKE_FAIL_STAGE:-}" == checker-stage && "$count" == 2 ]]; then
    printf 'staged checker failure\n' >&2
    exit 69
  fi
  if [[ "${FAKE_FAIL_STAGE:-}" == checker-commit && "$count" == 4 ]]; then
    root="${RELEASE_FIXTURE_ROOT:?}"
    expected="${RELEASE_EXPECTED_NEXT:?}"
    yaml_value="$(grep -m1 'CURRENT_PROJECT_VERSION:' "$root/ios/project.yml" | sed -E 's/.*CURRENT_PROJECT_VERSION:[^0-9]*([0-9]+).*/\1/')"
    manifest_value="$("${RELEASE_REAL_NODE:?}" -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).latestBuild" "$root/public/kuzey-version.json")"
    if [[ "$yaml_value" != "$expected" || "$manifest_value" != "$expected" ]]; then
      printf 'commit checker kaynak kurulmadan çağrıldı\n' >&2
      exit 72
    fi
    printf 'commit checker build %s gördü\n' "$expected" >> "${RELEASE_TEST_LOG:?}"
    printf 'committed checker failure\n' >&2
    exit 70
  fi
fi
exec "${RELEASE_REAL_NODE:?}" "$@"
SH

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
    CURRENT_PROJECT_VERSION="${RELEASE_EXPECTED_NEXT:?}") has_next=true; shift ;;
    *) shift ;;
  esac
done

if [[ "$stage" == archive && "$has_next" != true ]]; then
  printf 'archive CURRENT_PROJECT_VERSION=%s almadı\n' "$RELEASE_EXPECTED_NEXT" >&2
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
expected="${RELEASE_EXPECTED_CURRENT:?}"
yaml_values="$(grep 'CURRENT_PROJECT_VERSION:' "$root/ios/project.yml" | sed -E 's/.*CURRENT_PROJECT_VERSION:[^0-9]*([0-9]+).*/\1/' | sort -u | tr '\n' ' ')"
project_values="$(grep 'CURRENT_PROJECT_VERSION =' "$root/ios/Kuzey.xcodeproj/project.pbxproj" | sed -E 's/.*= ([0-9]+);/\1/' | sort -u | tr '\n' ' ')"
manifest_value="$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).latestBuild" "$root/public/kuzey-version.json")"
if [[ "$yaml_values" != "$expected " || "$project_values" != "$expected " || "$manifest_value" != "$expected" ]]; then
  printf 'kaynaklar yüklemeden önce değişti: yaml=%s pbx=%s manifest=%s\n' "$yaml_values" "$project_values" "$manifest_value" >&2
  exit 66
fi
printf 'upload kaynak build %s gördü\n' "$expected" >> "${RELEASE_TEST_LOG:?}"
if [[ "${FAKE_FAIL_STAGE:-}" == upload ]]; then
  printf 'upload failure\n' >&2
  exit 67
fi
printf 'UPLOAD SUCCEEDED\n'
SH

  cat > "$fixture/bin/xcodegen" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${FAKE_FAIL_STAGE:-}" == xcodegen ]]; then
  printf 'xcodegen failure\n' >&2
  exit 68
fi

stage_root="${KUZ_RELEASE_TRANSACTION_DIR:?}/staged"
next="${RELEASE_EXPECTED_NEXT:?}"
yaml_values="$(grep 'CURRENT_PROJECT_VERSION:' "$stage_root/ios/project.yml" | sed -E 's/.*CURRENT_PROJECT_VERSION:[^0-9]*([0-9]+).*/\1/' | sort -u | tr '\n' ' ')"
manifest_value="$(node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).latestBuild" "$stage_root/public/kuzey-version.json")"
if [[ "$yaml_values" != "$next " || "$manifest_value" != "$next" ]]; then
  printf 'xcodegen staged build kaydı tamamlanmadan çağrıldı\n' >&2
  exit 71
fi
CURRENT="${RELEASE_EXPECTED_CURRENT:?}" NEXT="$next" perl -0pi -e \
  's/CURRENT_PROJECT_VERSION = \Q$ENV{CURRENT}\E;/CURRENT_PROJECT_VERSION = $ENV{NEXT};/g' \
  "$stage_root/ios/Kuzey.xcodeproj/project.pbxproj"
SH

  chmod +x "$fixture/tools/testflight.sh" "$fixture/bin/node" "$fixture/bin/xcodebuild" \
    "$fixture/bin/xcrun" "$fixture/bin/xcodegen"
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

run_release() {
  local fixture="$1"
  local failure_stage="${2:-}"
  local current next
  current="$(<"$fixture/expected-current")"
  next="$(<"$fixture/expected-next")"
  : > "${fixture}/node-count"

  PATH="$fixture/bin:$PATH" \
    KUZ_RELEASE_TRANSACTION_DIR="$fixture/release-transaction" \
    RELEASE_FIXTURE_ROOT="$fixture" RELEASE_TEST_LOG="$fixture/release.log" \
    RELEASE_REAL_NODE="$real_node" RELEASE_NODE_COUNT="$fixture/node-count" \
    RELEASE_EXPECTED_CURRENT="$current" RELEASE_EXPECTED_NEXT="$next" \
    FAKE_FAIL_STAGE="$failure_stage" ASC_KEY_ID="test-key" ASC_ISSUER_ID="test-issuer" \
    bash "$fixture/tools/testflight.sh" >"$fixture/output.log" 2>&1
}

run_failure_case() {
  local stage="$1"
  local fixture current
  fixture="$(make_fixture "fail-$stage")"
  current="$(<"$fixture/expected-current")"
  : > "$fixture/release.log"

  if run_release "$fixture" "$stage"; then
    fail "$stage hatası release komutundan yayılmadı"
  fi
  assert_build "$fixture" "$current"
  if [[ "$stage" == xcodegen || "$stage" == checker-stage ]]; then
    test ! -s "$fixture/release.log" || fail "$stage hatası upload'dan önce durmalı"
  fi
  pass "$stage hatası kaynak build'i değiştirmeden yayıldı"
}

run_failure_case xcodegen
run_failure_case checker-stage
run_failure_case archive
run_failure_case export
run_failure_case upload

printf '\n=== Apple kabulünden sonra geri alınabilir kayıt ===\n'
commit_failure_fixture="$(make_fixture checker-commit)"
commit_current="$(<"$commit_failure_fixture/expected-current")"
commit_next="$(<"$commit_failure_fixture/expected-next")"
: > "$commit_failure_fixture/release.log"
if run_release "$commit_failure_fixture" checker-commit; then
  fail "kaynak commit checker hatası release komutundan yayılmadı"
fi
assert_build "$commit_failure_fixture" "$commit_current"
grep -Fxq "commit checker build $commit_next gördü" "$commit_failure_fixture/release.log" \
  || fail "enjekte edilen checker hatası kurulu sonraki build'i gözlemlemedi"
test -f "$commit_failure_fixture/release-transaction/upload-accepted" \
  || fail "Apple kabulünden sonra recovery işareti korunmadı"
upload_count="$(grep -c '^upload kaynak build ' "$commit_failure_fixture/release.log")"
[[ "$upload_count" == 1 ]] || fail "ilk release tam olarak bir upload yapmalı"
run_release "$commit_failure_fixture"
assert_build "$commit_failure_fixture" "$commit_next"
recovered_upload_count="$(grep -c '^upload kaynak build ' "$commit_failure_fixture/release.log")"
[[ "$recovered_upload_count" == 1 ]] || fail "recovery aynı build'i yeniden upload etmemeli"
test ! -e "$commit_failure_fixture/release-transaction" || fail "başarılı recovery transaction alanını temizlemeli"
if find "$commit_failure_fixture" -name '*.kuzey-release-pending' -print -quit | grep -q .; then
  fail "recovery bekleyen geçici kaynak dosyası bırakmamalı"
fi
pass "checker commit hatası tüm kaynakları geri aldı; recovery yeniden upload etmeden tamamlandı"

printf '\n=== Sürüm kaynağı kapsamı ===\n'
missing_config_fixture="$(make_fixture missing-project-config)"
missing_current="$(<"$missing_config_fixture/expected-current")"
CURRENT="$missing_current" perl -0pi -e \
  's/^\s*CURRENT_PROJECT_VERSION = \Q$ENV{CURRENT}\E;\n//m' \
  "$missing_config_fixture/ios/Kuzey.xcodeproj/project.pbxproj"
if node "$missing_config_fixture/tools/check-ios-release-version.mjs" \
  >"$missing_config_fixture/checker.log" 2>&1; then
  fail "sürüm kontrolü eksik pbx build ayarını kabul etti"
fi
pass "sürüm kontrolü app/widget yapılandırmalarından eksik build ayarını reddetti"

printf '\n=== Dinamik build ve açıklamalı YAML ===\n'
base_current="$(yaml_build "$root/ios/project.yml")"
bumped_current=$((base_current + 4))
bumped_fixture="$(make_fixture bumped "$bumped_current")"
perl -0pi -e 's/(CURRENT_PROJECT_VERSION: "[0-9]+")/$1 # release build/g' \
  "$bumped_fixture/ios/project.yml"
: > "$bumped_fixture/release.log"
run_release "$bumped_fixture" \
  || fail "artırılmış/açıklamalı fixture tamamlanmadı: $(<"$bumped_fixture/output.log")"
bumped_next="$(<"$bumped_fixture/expected-next")"
assert_build "$bumped_fixture" "$bumped_next"
comment_count="$(grep -c '# release build' "$bumped_fixture/ios/project.yml")"
[[ "$comment_count" == 2 ]] || fail "YAML satır içi açıklamaları sürüm artışında korunmadı"
grep -Fxq "upload kaynak build $bumped_current gördü" "$bumped_fixture/release.log" \
  || fail "dinamik fixture upload sırasında kaynak build'i korumadı"
if grep -Fq 'XXXXXX' "$bumped_fixture/public/kuzey-version.json"; then
  fail "başarılı kayıt manifestte yer tutucu URL bıraktı"
fi
pass "fixture $bumped_current → $bumped_next dinamik artışı ve YAML açıklamalarını korudu"

printf '\n✅ RELEASE GÜVENLİĞİ KONTROLLERİ GEÇTİ\n'
