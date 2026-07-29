#!/usr/bin/env bash
set -u

tests_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$tests_dir/../.." && pwd)"
source_dir="$root/ios/Karavan"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

failures=0

pass() {
  printf '  ✓ %s\n' "$1"
}

fail() {
  printf '  ✗ %s\n' "$1"
  failures=$((failures + 1))
}

printf '\n=== Saf izin politikası ===\n'
if [[ ! -f "$source_dir/PermissionPolicy.swift" ]]; then
  fail "PermissionPolicy.swift eksik"
elif swiftc -O -o "$out/permission-policy-check" \
  "$tests_dir/permission-policy-check.swift" \
  "$source_dir/PermissionPolicy.swift"; then
  if "$out/permission-policy-check"; then
    pass "izin politikası çalıştırıldı"
  else
    fail "izin politikası beklentileri"
  fi
else
  fail "izin politikası derlenemedi"
fi

printf '\n=== Otomatik istem bağlantıları ===\n'
app_source="$source_dir/KaravanApp.swift"
dashboard_source="$source_dir/Views/DashboardView.swift"
map_source="$source_dir/Views/MapScreen.swift"
location_source="$source_dir/LocationManager.swift"

if rg -q 'requestAuthorization\(\)' "$app_source"; then
  fail "uygulama başlangıcı bildirim izni istemiyor"
else
  pass "uygulama başlangıcı bildirim izni istemiyor"
fi

if rg -q 'loc\.request\(\)' "$dashboard_source" "$map_source"; then
  fail "Dashboard ve Harita önyüklemesi konum izni istemiyor"
else
  pass "Dashboard ve Harita önyüklemesi konum izni istemiyor"
fi

authorization_delegate="$(sed -n '/nonisolated func locationManagerDidChangeAuthorization/,/^    }$/p' "$location_source")"
if rg -q 'requestAlways(Authorization)?\(' <<<"$authorization_delegate"; then
  fail "konum yetki delegesi Her Zaman iznine yükseltmiyor"
else
  pass "konum yetki delegesi Her Zaman iznine yükseltmiyor"
fi

printf '\n=== Açık eylem bağlantıları ===\n'
for method in requestWhenInUse requestAlways startIfAuthorized openSettings; do
  if rg -q "func ${method}\\(\\)" "$location_source"; then
    pass "LocationManager.${method} mevcut"
  else
    fail "LocationManager.${method} eksik"
  fi
done

if rg -q 'status = manager\.authorizationStatus' "$location_source"; then
  pass "başlangıç yetki durumu CLLocationManager'dan okunuyor"
else
  fail "başlangıç yetki durumu CLLocationManager'dan okunmuyor"
fi

if rg -q 'guard status == \.authorizedAlways else \{ return \}' "$location_source"; then
  pass "durak izleme yalnızca Her Zaman izninde başlıyor"
else
  fail "durak izleme Her Zaman izniyle sınırlandırılmamış"
fi

if rg -q 'loc\.startIfAuthorized\(\)' "$dashboard_source" "$map_source"; then
  pass "Dashboard ve Harita yalnızca yetkili konumu başlatıyor"
else
  fail "Dashboard ve Harita yetkili konumu başlatmıyor"
fi

if rg -q 'location\.requestWhenInUse\(\)' "$source_dir/Views/Trips/PlacePickerView.swift"; then
  pass "Konumum eylemi Kullanırken iznini istiyor"
else
  fail "Konumum eylemi Kullanırken iznini istemiyor"
fi

if rg -q 'authorizationStatus' "$source_dir/Notifications.swift" \
  && rg -q 'refreshAuthorization\(\)' "$app_source"; then
  pass "bildirim durumu görünür ve aktif sahnede tazeleniyor"
else
  fail "bildirim durumu aktif sahnede tazelenmiyor"
fi

if rg -q 'Kalan mesafe, hız ve sıradaki durağı konumuna göre hesapla\.' "$source_dir/Views/LiveLocationCard.swift" \
  && rg -q 'Arka planda varışları aç' "$source_dir/Views/LiveLocationCard.swift" \
  && rg -q 'Kalkış, varış ve hava uyarılarını zamanında al\.' "$dashboard_source"; then
  pass "bağlamsal izin açıklamaları mevcut"
else
  fail "bağlamsal izin açıklamaları eksik"
fi

if rg -q 'if enabled, requestPermission, !NotificationManager\.shared\.authorized' \
  "$source_dir/Views/Latvian/LatvianCourseModel.swift"; then
  pass "Letonca hatırlatıcı açık eylemi korunuyor"
else
  fail "Letonca hatırlatıcı açık eylemi korunmuyor"
fi

if (( failures > 0 )); then
  printf '\n❌ %d izin kontrolü başarısız\n' "$failures"
  exit 1
fi

printf '\n✅ izin politikası ve bağlantıları geçti\n'
