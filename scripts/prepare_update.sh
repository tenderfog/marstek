#!/bin/zsh
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_dir='' run_id='' source_commit='' notes_file=''
while (( $# )); do
    case "$1" in
        --artifact-dir) artifact_dir="$2"; shift 2 ;;
        --run-id) run_id="$2"; shift 2 ;;
        --source-commit) source_commit="$2"; shift 2 ;;
        --notes-file) notes_file="$2"; shift 2 ;;
        *) printf '%s\n' 'Usage: prepare_update.sh --artifact-dir DIR --run-id ID --source-commit SHA [--notes-file FILE]' >&2; exit 1 ;;
    esac
done
[[ -f "$artifact_dir/VenusBar.zip" && "$run_id" =~ '^[1-9][0-9]*$' && "$source_commit" =~ '^[a-f0-9]{40}$' ]] || { printf '%s\n' 'A CI artifact directory, numeric run ID and full source commit are required.' >&2; exit 1; }
[[ -z "$notes_file" || -f "$notes_file" ]] || { printf '%s\n' 'Notes file does not exist.' >&2; exit 1; }
python3 - "$artifact_dir" <<'PY'
import hashlib, pathlib, re, sys
artifact = pathlib.Path(sys.argv[1])
lines = (artifact/'SHA256SUMS.txt').read_text().splitlines()
expected = next((line.split()[0] for line in lines if re.fullmatch(r'[a-f0-9]{64}  VenusBar\.zip', line)), None)
if expected != hashlib.sha256((artifact/'VenusBar.zip').read_bytes()).hexdigest():
    raise SystemExit('The CI artifact checksum is missing or incorrect.')
PY
mkdir -p "$project_root/.build"
stage="$(mktemp -d "$project_root/.build/prepare-update.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/archive" "$stage/app"
cp "$artifact_dir/VenusBar.zip" "$stage/archive/VenusBar.zip"
unzip -tq "$stage/archive/VenusBar.zip"
/usr/bin/ditto -x -k "$stage/archive/VenusBar.zip" "$stage/app"
python3 - "$project_root" "$stage" "$source_commit" "$run_id" "$notes_file" <<'PY'
import hashlib, html, json, pathlib, plistlib, sys
root, stage = map(pathlib.Path, sys.argv[1:3])
commit, run_id, notes_file = sys.argv[3:]
with (stage/'app/VenusBar.app/Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
config = json.loads((root/'Config/Release.json').read_text())
if info.get('CFBundleShortVersionString') != config['version'] or info.get('CFBundleVersion') != str(config['build']):
    raise SystemExit('CI artifact version does not match Config/Release.json.')
if info.get('SUPublicEDKey') != (root/'Config/UpdatePublicKey.txt').read_text().strip():
    raise SystemExit('CI artifact has a different update public key.')
if info.get('CFBundleIdentifier') != 'local.offline.VenusBar':
    raise SystemExit('CI artifact has a different bundle identifier.')
archive = stage/'archive/VenusBar.zip'
manifest = dict(version=config['version'], build=config['build'], sourceCommit=commit, runID=int(run_id), artifactName='VenusBar-universal', zipSHA256=hashlib.sha256(archive.read_bytes()).hexdigest())
(stage/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
notes = pathlib.Path(notes_file).read_text().strip() if notes_file else f"VenusBar {config['version']} · build {config['build']}."
(stage/'archive/VenusBar.html').write_text('<p>'+html.escape(notes).replace('\n','<br>\n')+'</p>\n')
PY
version="$(/usr/bin/plutil -extract version raw -o - "$stage/manifest.json")"
build="$(/usr/bin/plutil -extract build raw -o - "$stage/manifest.json")"
sparkle_path="$(zsh "$project_root/scripts/fetch_sparkle.sh")"
"$sparkle_path/bin/generate_appcast" --account tenderfog.VenusBar \
    --maximum-deltas 0 --maximum-versions 1 --embed-release-notes \
    --link 'https://github.com/tenderfog/marstek' \
    --full-release-notes-url 'https://github.com/tenderfog/marstek/blob/main/CHANGELOG.md' \
    --download-url-prefix "https://github.com/tenderfog/marstek/releases/download/v$version-build$build/" \
    -o "$stage/appcast.xml" "$stage/archive"
"$sparkle_path/bin/sign_update" --account tenderfog.VenusBar --verify "$stage/appcast.xml"
archive_signature="$(python3 - "$stage/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
item = ET.parse(sys.argv[1]).getroot().find('channel/item/enclosure')
signature = item.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature', '') if item is not None else ''
if not signature: raise SystemExit('Missing archive signature: check your Keychain signing key.')
print(signature)
PY
)"
"$sparkle_path/bin/sign_update" --account tenderfog.VenusBar --verify "$stage/archive/VenusBar.zip" "$archive_signature"
mkdir -p "$project_root/releases/current"
cp "$stage/manifest.json" "$project_root/releases/current/manifest.json"
cp "$stage/appcast.xml" "$project_root/releases/current/appcast.xml"
printf '%s\n' 'Prepared releases/current/manifest.json and signed appcast.xml. Review and push these files to publish. No private key was exported.'
