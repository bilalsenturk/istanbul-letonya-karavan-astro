#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

revision="${1:-HEAD}"
git rev-parse --verify --quiet "${revision}^{commit}" >/dev/null

source_for() {
  git show "${revision}:$1"
}

app="$(source_for ios/Karavan/KaravanApp.swift)"
content="$(source_for ios/Karavan/Views/ContentView.swift)"
navigation="$(source_for ios/Karavan/Navigation.swift)"
plan="$(source_for ios/Karavan/Views/PlanScreen.swift)"

require_source() {
  local source="$1"
  local needle="$2"
  local message="$3"

  if ! grep -Fq "$needle" <<<"$source"; then
    printf '❌ %s\n' "$message" >&2
    exit 1
  fi
}

reject_source() {
  local source="$1"
  local needle="$2"
  local message="$3"

  if grep -Fq "$needle" <<<"$source"; then
    printf '❌ %s\n' "$message" >&2
    exit 1
  fi
}

require_source "$app" '@StateObject private var appNavigation = AppNavigation.shared' 'KaravanApp paylaşılan navigasyon durumunu oluşturmalı.'
require_source "$app" '.environmentObject(appNavigation)' 'KaravanApp navigasyon durumunu görünüm ağacına aktarmalı.'
require_source "$content" 'TabView(selection: $appNavigation.selectedTab)' 'ContentView paylaşılan sekme seçimini kullanmalı.'

for tab in dashboard plan journal tools; do
  require_source "$content" ".tag(AppTab.$tab)" "ContentView AppTab.$tab sekmesini içermeli."
done

tab_count="$(grep -oE '\.tag\(AppTab\.[[:alnum:]_]+\)' <<<"$content" | wc -l | tr -d ' ')"
if [[ "$tab_count" != "4" ]]; then
  printf '❌ ContentView tam olarak dört uygulama sekmesi içermeli (bulunan: %s).\n' "$tab_count" >&2
  exit 1
fi

reject_source "$content" '.tag(AppTab.map)' 'Harita ayrı bir sekme olmamalı.'
reject_source "$navigation" 'case map' 'AppTab ayrı bir harita durumu tanımlamamalı.'
require_source "$navigation" 'if arguments.contains("-ui-preview-map") { selectedTab = .plan }' 'Harita önizlemesi Plan sekmesine yönlenmeli.'

require_source "$plan" 'Button { showMap = true }' 'Plan ekranı haritayı açan düğmeyi içermeli.'
require_source "$plan" '.fullScreenCover(isPresented: $showMap)' 'Plan ekranı haritayı tam ekran sunmalı.'
require_source "$plan" 'PlanMapView()' 'Plan ekranı PlanMapView içeriğini sunmalı.'

printf '✅ PAYLAŞILAN GEZİ NAVİGASYONU BAĞLANTILARI GEÇTİ (%s)\n' "$revision"
