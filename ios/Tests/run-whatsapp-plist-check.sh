#!/usr/bin/env bash
set -euo pipefail

project_yml="$(git show HEAD:ios/project.yml)"
info_plist="$(git show HEAD:ios/Support/Info.plist)"

printf '%s\n' "$project_yml" | rg -U 'LSApplicationQueriesSchemes:\s*\n\s*- whatsapp' >/dev/null
printf '%s\n' "$info_plist" | rg -U '<key>LSApplicationQueriesSchemes</key>\s*<array>\s*<string>whatsapp</string>' >/dev/null
echo 'Committed WhatsApp application-query scheme is present in project.yml and Info.plist.'
