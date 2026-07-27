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

grep -Fq '@StateObject private var appNavigation = AppNavigation.shared' <<<"$app"
grep -Fq '.environmentObject(appNavigation)' <<<"$app"
grep -Fq 'TabView(selection: $appNavigation.selectedTab)' <<<"$content"

for tab in dashboard map plan journal tools; do
  grep -Fq ".tag(AppTab.$tab)" <<<"$content"
done

grep -Fq 'case map' <<<"$navigation"
grep -Fq 'if arguments.contains("-ui-preview-map") { selectedTab = .map }' <<<"$navigation"

printf '✅ PAYLAŞILAN GEZİ NAVİGASYONU BAĞLANTILARI GEÇTİ (%s)\n' "$revision"
