#!/usr/bin/env bash
set -euo pipefail

# Cupola icon pipeline
# ---------------------
# Everything the app ships as an icon descends from scripts/icons/masters.py,
# where the geometry lives as constants. Nothing downstream carries geometry, so
# changing the mark means editing that one file and running --write.
#
#   scripts/generate_icons.sh --write             regenerate every target in place
#   scripts/generate_icons.sh --check             (default) validate sources + manifest
#   scripts/generate_icons.sh --refresh-manifest  re-record output hashes
#
# --write needs python3 with Pillow, plus node/npx for the SVG rasteriser. It is
# a developer-machine operation: CI only ever runs --check, which needs neither.
#
# What --write produces:
#   assets/brand/*.svg      the three canonical compositions (mark, full ground,
#                           simplified small-size variant)
#   assets/brand/cupola_mark.png  the in-app mark drawn by ServiceRing, a real
#                           app asset declared in pubspec.yaml, not scratch
#   ios|macos .icon/Assets  Icon Composer layers, light and dark groups
#   macos cupola_icon_legacy.icns  the macOS fallback, for systems that predate
#                           Icon Composer (dark appearance; it has no appearance
#                           channel). Neither Apple platform has an .appiconset:
#                           actool ignores one when the app icon is a .icon bundle,
#                           and iOS's fallback is derived by actool itself
#   android res/mipmap-*    light appearance, plus mipmap-night-* for dark and
#                           an adaptive foreground for each
#   android res/drawable*   the adaptive backgrounds, one per appearance
#   launch screens          the mark at 112pt over the room's ground: iOS's
#                           LaunchImage.imageset, Android's drawable-*/launch_mark,
#                           and the same mark on a clear 288dp canvas for
#                           Android 12's splash (drawable-*/launch_splash_mark)
#   web, windows, linux     favicons, maskable icons, .ico, hicolor set
#
# The manifest refresh stays deliberate: --write never touches
# scripts/icon_outputs.json, so output changes get reviewed before being
# re-recorded. scripts/verify_icons.sh is the gate.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BRAND_DIR="$ROOT_DIR/assets/brand"
MODE=check
OUTPUT_DIR="$ROOT_DIR/.ai/generated-icons"
MANIFEST="$ROOT_DIR/scripts/icon_outputs.json"

usage() {
  printf 'Usage: %s [--check] | [--write] | [--refresh-manifest]\n' "${0##*/}"
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage
  exit 0
elif [[ ${1:-} == "--check" || -z ${1:-} ]]; then
  MODE=check
elif [[ ${1:-} == "--write" ]]; then
  MODE=write
  [[ -z ${2:-} ]] || { usage >&2; exit 2; }
elif [[ ${1:-} == "--refresh-manifest" ]]; then
  MODE=refresh_manifest
  [[ -z ${2:-} ]] || { usage >&2; exit 2; }
else
  usage >&2
  exit 2
fi

if [[ $MODE == write ]]; then
  command -v python3 >/dev/null 2>&1 || {
    printf 'error: --write requires python3\n' >&2; exit 1; }
  python3 -c 'import PIL' >/dev/null 2>&1 || {
    printf 'error: --write requires Pillow (pip install Pillow)\n' >&2; exit 1; }
  command -v npx >/dev/null 2>&1 || {
    printf 'error: --write requires node/npx for the SVG rasteriser\n' >&2; exit 1; }
  [[ -d "$ROOT_DIR/scripts/icons/node_modules" ]] || {
    printf 'error: install the pinned rasteriser first:\n  npm ci --prefix scripts/icons\n' >&2
    exit 1
  }

  BUILD_DIR="$ROOT_DIR/scripts/icons/.build"
  rm -rf "$BUILD_DIR"
  python3 "$ROOT_DIR/scripts/icons/masters.py" --out "$BUILD_DIR" --brand "$BRAND_DIR"
  python3 "$ROOT_DIR/scripts/icons/export.py" --repo "$ROOT_DIR" --masters "$BUILD_DIR"
  printf '\nReview the diff, then record it:\n  scripts/generate_icons.sh --refresh-manifest\n  scripts/verify_icons.sh\n'
  exit 0
fi

for required in cupola_mark.svg cupola_icon.svg cupola_launcher.svg; do
  [[ -f "$BRAND_DIR/$required" ]] || {
    printf 'error: missing canonical asset: %s\n' "$BRAND_DIR/$required" >&2
    exit 1
  }
done

command -v python3 >/dev/null 2>&1 || {
  printf 'error: python3 is required for SVG validation\n' >&2
  exit 1
}

python3 - "$BRAND_DIR" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

brand = Path(sys.argv[1])
for name in ("cupola_mark.svg", "cupola_icon.svg", "cupola_launcher.svg"):
    root = ET.parse(brand / name).getroot()
    if root.tag != "{http://www.w3.org/2000/svg}svg":
        raise SystemExit(f"error: {name} is not an SVG document")
    if root.get("viewBox") != "0 0 1024 1024":
        raise SystemExit(f"error: {name} must use viewBox 0 0 1024 1024")
print("SVG check: 3 canonical 1024x1024 assets are valid")
PY

python3 - "$ROOT_DIR" "$MANIFEST" "$MODE" <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
mode = sys.argv[3]

canonical_sources = [
    {"path": "assets/brand/cupola_mark.svg", "role": "geometry source of record", "source_family": "canonical"},
    {"path": "assets/brand/cupola_icon.svg", "role": "full-ground composition", "source_family": "canonical"},
    {"path": "assets/brand/cupola_launcher.svg", "role": "small-size variant", "source_family": "canonical"},
]

def paths(pattern):
    return sorted(path.relative_to(root).as_posix() for path in root.glob(pattern) if path.is_file())

def output_paths():
    result = set()
    result.update(paths("android/app/src/main/res/**/cupola_icon*.xml"))
    result.update(paths("android/app/src/main/res/**/cupola_icon*.webp"))
    result.update(paths("android/app/src/main/AndroidManifest.xml"))
    for platform in ("ios", "macos"):
        result.update(paths(f"{platform}/Runner/cupola_icon.icon/icon.json"))
        result.update(paths(f"{platform}/Runner/cupola_icon.icon/Assets/*.png"))
        result.update(paths(f"{platform}/Runner.xcodeproj/project.pbxproj"))
    # Only macOS has a fallback of our own to write; actool derives iOS's from the
    # .icon and names it in the Info.plist, so there is nothing here to track.
    result.update(paths("macos/Runner/cupola_icon_legacy.icns"))
    result.update(paths("web/icons/*.png"))
    result.update(paths("web/favicon*.png"))
    result.update(paths("web/manifest.json"))
    result.update(paths("web/index.html"))
    result.update(paths("windows/runner/resources/app_icon.ico"))
    result.update(paths("windows/runner/Runner.rc"))
    result.update(paths("linux/CMakeLists.txt"))
    result.update(paths("linux/runner/cupola.desktop"))
    result.update(paths("linux/runner/icons/hicolor/*x*/apps/cupola.png"))
    return sorted(result)

def source_family(path):
    if path.startswith("android/"):
        return "cupola_mark.svg + cupola_launcher.svg"
    if path.startswith(("ios/", "macos/")):
        return "cupola_icon.svg + cupola_launcher.svg"
    return "cupola_icon.svg"

def role(path):
    if path.endswith("AndroidManifest.xml"):
        return "Android icon entry points"
    if path.endswith(".xml"):
        return "Android icon resource/config"
    if path.startswith("android/"):
        return "Android launcher output"
    if ".icon/" in path:
        return "Apple Icon Composer active input"
    if path.endswith("cupola_icon_legacy.icns"):
        return "macOS pre-Icon Composer fallback output"
    if path.startswith(("ios/", "macos/")):
        return "Apple active project icon config"
    if path.startswith("web/"):
        return "web icon output/config"
    if path.endswith("app_icon.ico"):
        return "Windows launcher output"
    if path.endswith("Runner.rc"):
        return "Windows launcher resource config"
    if path.endswith("cupola.desktop"):
        return "Linux desktop entry"
    if path.endswith("linux/CMakeLists.txt"):
        return "Linux icon install config"
    return "Linux hicolor launcher output/install config"

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def build_manifest():
    return {
        "version": 1,
        "canonical_sources": canonical_sources,
        "outputs": [
            {
                "path": path,
                "role": role(path),
                "source_family": source_family(path),
                "sha256": sha256(root / path),
            }
            for path in output_paths()
        ],
    }

def check_manifest():
    if not manifest_path.is_file():
        raise SystemExit(f"error: missing manifest: {manifest_path}")
    try:
        data = json.loads(manifest_path.read_text())
    except (OSError, ValueError) as exc:
        raise SystemExit(f"error: invalid manifest: {exc}")
    if data.get("version") != 1 or data.get("canonical_sources") != canonical_sources:
        raise SystemExit("error: manifest version or canonical source policy is incorrect")
    entries = data.get("outputs")
    if not isinstance(entries, list):
        raise SystemExit("error: manifest outputs must be a list")
    expected = output_paths()
    actual = [entry.get("path") for entry in entries]
    if actual != expected:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise SystemExit(f"error: manifest output paths differ (missing={missing}, extra={extra})")
    for entry in entries:
        path = root / entry["path"]
        if not path.is_file():
            raise SystemExit(f"error: manifest path does not exist: {entry['path']}")
        if entry.get("role") != role(entry["path"]) or entry.get("source_family") != source_family(entry["path"]):
            raise SystemExit(f"error: manifest metadata is incorrect: {entry['path']}")
        actual_hash = sha256(path)
        if entry.get("sha256") != actual_hash:
            raise SystemExit(f"error: manifest hash mismatch: {entry['path']}")
    print(f"Manifest check: {len(entries)} output hashes match")

if mode == "refresh_manifest":
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    temporary.write_text(json.dumps(build_manifest(), indent=2) + "\n")
    os.replace(temporary, manifest_path)
    print(f"Manifest refreshed explicitly: {manifest_path}")
elif mode == "check":
    check_manifest()
PY

if [[ $MODE == check ]]; then
  printf 'Check-only mode: no files written.\n'
fi
exit 0
