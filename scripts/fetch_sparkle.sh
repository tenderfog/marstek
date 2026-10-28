#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(/usr/bin/plutil -extract version raw -o - "$project_root/Config/Sparkle.json")"
download_url="$(/usr/bin/plutil -extract url raw -o - "$project_root/Config/Sparkle.json")"
expected_sha="$(/usr/bin/plutil -extract sha256 raw -o - "$project_root/Config/Sparkle.json")"
destination="$project_root/.build/sparkle/$version"
# Recheck the pinned archive even when the extracted framework is cached.
mkdir -p "$project_root/.build/downloads" "$(dirname "$destination")"
archive="$project_root/.build/downloads/Sparkle-$version.tar.xz"
if [[ ! -f "$archive" ]] || [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" != "$expected_sha" ]]; then
    temp_archive="$(mktemp "$project_root/.build/downloads/Sparkle.XXXXXX")"
    trap 'rm -f "$temp_archive"' EXIT
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 "$download_url" -o "$temp_archive"
    [[ "$(shasum -a 256 "$temp_archive" | cut -d ' ' -f 1)" == "$expected_sha" ]] || { printf '%s\n' 'Sparkle checksum mismatch.' >&2; exit 1; }
    mv "$temp_archive" "$archive"
fi
# Extract from verified bytes so editing a cached framework cannot affect a build.
temp_root="$(mktemp -d "$project_root/.build/sparkle/extract.XXXXXX")"
trap 'rm -rf "$temp_root"' EXIT
tar -xJf "$archive" -C "$temp_root"
[[ -d "$temp_root/Sparkle.framework" && -x "$temp_root/bin/sign_update" && -x "$temp_root/bin/generate_appcast" ]]
rm -rf "$destination"
mv "$temp_root" "$destination"
printf '%s\n' "$destination"
