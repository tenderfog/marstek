#!/bin/zsh
set -euo pipefail

# Produces a standalone menu-bar app and ZIP. Python is used ONLY to write the
# development-toolchain overlay; no interpreter, source path or user data ships.
# The only executed app mode is --self-check (pure; no LAN/control/UI requests).
project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$project_root/Sources/VenusBar"
output_root="$project_root/build"
work_root="$project_root/.build/venusbar"
app_path="$output_root/VenusBar.app"
zip_path="$output_root/VenusBar.zip"

if [[ ! -f "$source_root/VenusBarApp.swift" ]]; then
    printf '%s\n' 'Немає точки входу Sources/VenusBar/VenusBarApp.swift; попередню збірку не змінено.' >&2
    exit 1
fi

mkdir -p "$work_root" "$output_root"
sparkle_root="$(zsh "$project_root/scripts/fetch_sparkle.sh")"
release_version="$(/usr/bin/plutil -extract version raw -o - "$project_root/Config/Release.json")"
release_build="$(/usr/bin/plutil -extract build raw -o - "$project_root/Config/Release.json")"
public_update_key="$(cat "$project_root/Config/UpdatePublicKey.txt")"
[[ "$release_version" =~ '^[0-9]+(\.[0-9]+){1,2}$' && "$release_build" =~ '^[1-9][0-9]*$' ]] || { printf '%s\n' 'Invalid release version/build.' >&2; exit 1; }
[[ "$(printf '%s' "$public_update_key" | /usr/bin/base64 -D | wc -c | tr -d ' ')" == 32 ]] || { printf '%s\n' 'Invalid Sparkle public key.' >&2; exit 1; }
stage_path="$(mktemp -d "$work_root/package.XXXXXX")"
promotion_started=false
promotion_complete=false
had_previous_app=false
had_previous_zip=false
cleanup_package() {
    local saved_exit=$?
    set +e
    if [[ "$promotion_started" == true && "$promotion_complete" != true ]]; then
        if [[ -e "$stage_path/previous-VenusBar.app" ]]; then
            rm -rf "$app_path"
            mv "$stage_path/previous-VenusBar.app" "$app_path"
        elif [[ "$had_previous_app" == false ]]; then
            rm -rf "$app_path"
        fi
        if [[ -e "$stage_path/previous-VenusBar.zip" ]]; then
            rm -f "$zip_path"
            mv "$stage_path/previous-VenusBar.zip" "$zip_path"
        elif [[ "$had_previous_zip" == false ]]; then
            rm -f "$zip_path"
        fi
    fi
    if [[ "$promotion_complete" != true && ( -e "$stage_path/previous-VenusBar.app" || -e "$stage_path/previous-VenusBar.zip" ) ]]; then
        printf 'Попередні артефакти збережено для відновлення: %s\n' "$stage_path" >&2
    else
        rm -rf "$stage_path"
    fi
    return "$saved_exit"
}
trap cleanup_package EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
stage_app="$stage_path/VenusBar.app"
mkdir -p "$stage_path/sources" "$stage_app/Contents/MacOS" "$stage_app/Contents/Resources"
mkdir -p "$stage_app/Contents/Frameworks"
/usr/bin/ditto "$sparkle_root/Sparkle.framework" "$stage_app/Contents/Frameworks/Sparkle.framework"
# Freeze one source revision for both architecture slices.
cp "$source_root"/*.swift "$stage_path/sources/"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$stage_app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$project_root/Assets/AppIcon/VenusBar.icns" "$stage_app/Contents/Resources/VenusBar.icns"
cp "$project_root/Assets/AppIcon/SOURCE.md" "$stage_app/Contents/Resources/MARSTEK_ICON_SOURCE.md"

if swift --version 2>/dev/null | /usr/bin/grep -q 'Swift version 6.0' && [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk"
else
    export SDKROOT="${SDKROOT:-$(xcrun --show-sdk-path)}"
fi

compiler_flags=()
swift_include="$(dirname "$(dirname "$(xcrun --find swiftc)")")/include/swift"
if [[ -f "$swift_include/module.modulemap" && -f "$swift_include/bridging.modulemap" ]] && \
    /usr/bin/grep -q 'module SwiftBridging' "$swift_include/module.modulemap" && \
    /usr/bin/grep -q 'module SwiftBridging' "$swift_include/bridging.modulemap"; then
    overlay_path="$stage_path/swift-module-overlay.json"
    python3 - "$swift_include/module.modulemap" "$stage_path/empty.modulemap" "$overlay_path" <<'PY'
import json
import sys
from pathlib import Path
old_map, empty_map, overlay = sys.argv[1:]
Path(empty_map).write_text("")
Path(overlay).write_text(json.dumps({"version": 0, "roots": [
    {"type": "file", "name": old_map, "external-contents": empty_map}
]}))
PY
    compiler_flags=(-vfsoverlay "$overlay_path" -Xcc -ivfsoverlay -Xcc "$overlay_path")
fi

cat > "$stage_path/SDKProbe.swift" <<'SWIFT'
import Foundation
import AppKit
import SwiftUI
struct VenusSDKProbe {}
SWIFT

architectures=()
binaries=()
for architecture in arm64 x86_64; do
    cache_path="$work_root/module-cache/$architecture"
    mkdir -p "$cache_path"
    export CLANG_MODULE_CACHE_PATH="$cache_path"
    export SWIFTPM_MODULECACHE_OVERRIDE="$cache_path"
    common_flags=(-sdk "$SDKROOT" -target "$architecture-apple-macosx13.0" \
        -swift-version 5 -module-cache-path "$cache_path" "${compiler_flags[@]}" -parse-as-library)
    if ! xcrun swiftc "${common_flags[@]}" -emit-object "$stage_path/SDKProbe.swift" \
        -o "$stage_path/probe-$architecture.o" > "$stage_path/probe-$architecture.log" 2>&1; then
        printf 'SDK/компілятор не підтримує %s; цей варіант пропущено.\n' "$architecture" >&2
        cat "$stage_path/probe-$architecture.log" >&2
        continue
    fi
    printf 'Компіляція VenusBar для %s…\n' "$architecture"
    binary_path="$stage_path/VenusBar-$architecture"
    xcrun swiftc "${common_flags[@]}" -F "$sparkle_root" -framework Sparkle \
        -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
        -O "$stage_path/sources"/*.swift -o "$binary_path"
    architectures+=("$architecture")
    binaries+=("$binary_path")
done

host_architecture="$(uname -m)"
if (( ${#architectures[@]} == 0 )) || [[ " ${architectures[*]} " != *" $host_architecture "* ]]; then
    printf '%s\n' 'Не вдалося зібрати варіант для цього Mac; попередню збірку не змінено.' >&2
    exit 1
fi
if (( ${#binaries[@]} == 2 )); then
    xcrun lipo -create "${binaries[@]}" -output "$stage_app/Contents/MacOS/VenusBar"
else
    cp "${binaries[1]}" "$stage_app/Contents/MacOS/VenusBar"
    printf '%s\n' 'Увага: ця збірка підтримує лише одну архітектуру.' >&2
fi
chmod 755 "$stage_app/Contents/MacOS/VenusBar"

cat > "$stage_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>VenusBar</string>
    <key>CFBundleIdentifier</key><string>local.offline.VenusBar</string>
    <key>CFBundleName</key><string>VenusBar</string>
    <key>CFBundleDisplayName</key><string>VenusBar</string>
    <key>CFBundleIconFile</key><string>VenusBar.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>4</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/tenderfog/marstek/releases/latest/download/appcast.xml</string>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SURequireSignedFeed</key><true/>
    <key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>SUAllowsAutomaticUpdates</key><false/>
    <key>SUAutomaticallyUpdate</key><false/>
    <key>SUEnableSystemProfiling</key><false/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>VenusBar знаходить ваші станції MARSTEK та читає їхні показники в домашній локальній мережі. Налаштування змінюються лише за вашою командою.</string>
</dict>
</plist>
PLIST
/usr/bin/plutil -replace CFBundleShortVersionString -string "$release_version" "$stage_app/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$release_build" "$stage_app/Contents/Info.plist"
/usr/bin/plutil -insert SUPublicEDKey -string "$public_update_key" "$stage_app/Contents/Info.plist"
/usr/bin/plutil -lint "$stage_app/Contents/Info.plist"
signing_identity="${VENUSBAR_CODESIGN_IDENTITY:--}"
if [[ "$signing_identity" == '-' ]]; then
    # Ad hoc builds cannot use Hardened Runtime library validation with Sparkle.
    /usr/bin/codesign --force --sign - --timestamp=none "$stage_app"
else
    sparkle_framework="$stage_app/Contents/Frameworks/Sparkle.framework"
    /usr/bin/codesign --force --sign "$signing_identity" --options runtime "$sparkle_framework/Versions/B/XPCServices/Installer.xpc"
    /usr/bin/codesign --force --sign "$signing_identity" --options runtime --preserve-metadata=entitlements "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc"
    /usr/bin/codesign --force --sign "$signing_identity" --options runtime "$sparkle_framework/Versions/B/Autoupdate"
    /usr/bin/codesign --force --sign "$signing_identity" --options runtime "$sparkle_framework/Versions/B/Updater.app"
    /usr/bin/codesign --force --sign "$signing_identity" --options runtime "$sparkle_framework"
    /usr/bin/codesign --force --sign "$signing_identity" --options runtime "$stage_app"
fi
/usr/bin/codesign --verify --deep --strict --verbose=2 "$stage_app"
"$stage_app/Contents/MacOS/VenusBar" --self-check
# App-only archive prevents translocation issues and is usable by Sparkle.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$stage_app" "$stage_path/VenusBar.zip"

# Only generated VenusBar artifacts are replaced, after compile/sign/check pass.
[[ ! -e "$app_path" ]] || had_previous_app=true
[[ ! -e "$zip_path" ]] || had_previous_zip=true
promotion_started=true
if [[ -e "$app_path" ]]; then mv "$app_path" "$stage_path/previous-VenusBar.app"; fi
if [[ -e "$zip_path" ]]; then mv "$zip_path" "$stage_path/previous-VenusBar.zip"; fi
mv "$stage_app" "$app_path"
mv "$stage_path/VenusBar.zip" "$zip_path"
promotion_complete=true
printf 'VenusBar.app: %s\nVenusBar.zip: %s\nАрхітектури: %s\n' "$app_path" "$zip_path" "${architectures[*]}"
if [[ "$signing_identity" == '-' ]]; then
    printf '%s\n' 'Підпис ad hoc; Apple Developer ID і нотаризацію не виконано.'
else
    printf '%s\n' 'Застосунок підписано; нотаризацію потрібно виконати окремо перед публікацією.'
fi
