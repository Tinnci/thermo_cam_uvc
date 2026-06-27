#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

resources_path="${1:-Resources}"
info_plist="${2:-Info.plist}"
canonical_language="en"
string_tables=("Localizable.strings" "InfoPlist.strings")
temporary_files=()

cleanup() {
  if (( ${#temporary_files[@]} > 0 )); then
    rm -f "${temporary_files[@]}"
  fi
}
trap cleanup EXIT

make_temp_file() {
  local path
  path="$(mktemp)"
  temporary_files+=("$path")
  printf '%s\n' "$path"
}

extract_keys() {
  local strings_file="$1"
  plutil -convert json -o - "$strings_file" \
    | /usr/bin/ruby -rjson -e 'puts JSON.parse(STDIN.read).keys.sort'
}

if [[ ! -d "$resources_path" ]]; then
  echo "Localization resources not found: $resources_path" >&2
  exit 1
fi

languages=()
while IFS= read -r language; do
  languages+=("$language")
done < <(find "$resources_path" -mindepth 1 -maxdepth 1 -type d -name '*.lproj' \
  -exec basename {} .lproj \; | sort)

if (( ${#languages[@]} == 0 )); then
  echo "No .lproj localization directories found in $resources_path" >&2
  exit 1
fi

if [[ -f "$info_plist" ]]; then
  declared_file="$(make_temp_file)"
  actual_file="$(make_temp_file)"
  plutil -convert json -o - "$info_plist" \
    | /usr/bin/ruby -rjson -e 'puts Array(JSON.parse(STDIN.read)["CFBundleLocalizations"]).sort' \
    > "$declared_file"
  printf '%s\n' "${languages[@]}" | sort > "$actual_file"

  if ! diff -u "$declared_file" "$actual_file"; then
    echo "CFBundleLocalizations does not match bundled .lproj directories" >&2
    exit 1
  fi
fi

for table in "${string_tables[@]}"; do
  canonical_file="$resources_path/$canonical_language.lproj/$table"
  if [[ ! -f "$canonical_file" ]]; then
    echo "Canonical localization table missing: $canonical_file" >&2
    exit 1
  fi

  canonical_keys="$(make_temp_file)"
  plutil -lint "$canonical_file"
  extract_keys "$canonical_file" > "$canonical_keys"

  for language in "${languages[@]}"; do
    localized_file="$resources_path/$language.lproj/$table"
    if [[ "$localized_file" == "$canonical_file" ]]; then
      continue
    fi

    if [[ ! -f "$localized_file" ]]; then
      echo "Localization table missing: $localized_file" >&2
      exit 1
    fi

    localized_keys="$(make_temp_file)"
    plutil -lint "$localized_file"
    extract_keys "$localized_file" > "$localized_keys"

    if ! diff -u "$canonical_keys" "$localized_keys"; then
      echo "Localization key mismatch: $localized_file" >&2
      exit 1
    fi
  done
done

echo "Localization verified for: ${languages[*]}"
