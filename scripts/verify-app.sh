#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

app_path="${1:-.build/ThermoCamUVC.app}"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  echo "Run scripts/build-local.sh first." >&2
  exit 1
fi

plutil -lint "$app_path/Contents/Info.plist"
if [[ -d "$app_path/Contents/Resources" ]]; then
  scripts/verify-localization.sh "$app_path/Contents/Resources" "$app_path/Contents/Info.plist"
fi
codesign --verify --deep --strict --verbose=2 "$app_path"
codesign -d --entitlements :- "$app_path" >/dev/null 2>&1
