#!/usr/bin/env bash
set -euo pipefail

# Cupola icon source policy
# -------------------------
# - assets/brand/cupola_mark.svg is the ONLY geometry source of record. Do not
#   add geometry to this script or derive geometry from a raster export.
# - assets/brand/cupola_icon.svg is the active full-ground/preview composition:
#   it intentionally owns its opaque ground and halo for previews and store art.
# - assets/brand/cupola_launcher.svg is the active simplified launcher variant;
#   its heavier ribs and oculus are intentional small-size geometry.
# - The Apple Icon Composer bundles are active Apple inputs, selected by both
#   Xcode projects: ios/Runner/cupola_icon.icon/ and
#   macos/Runner/cupola_icon.icon/. Each bundle's icon.json and layer PNGs are
#   intentional build inputs, not orphaned source families.
# - The traditional Apple catalogs are synchronized compatibility/fallback
#   outputs: ios/Runner/Assets.xcassets/AppIcon.appiconset/ and
#   macos/Runner/Assets.xcassets/AppIcon.appiconset/. Keep them aligned with
#   the active Icon Composer bundles for tooling and older build paths.
# - Active output families are android/app/src/main/res/ (Android), the Apple
#   Icon Composer bundles above, the Apple fallback catalogs above, web/ (web),
#   windows/ (Windows), and linux/ (Linux). These are consumers or synchronized
#   outputs, not additional geometry sources of truth.
# - Intentionally retained scratch/orphan paths are assets/brand/cupola_mark.png,
#   assets/icon/, and android/app/src/main/cupola_icon-playstore.png. The
#   .ai/generated-icons/ directory is also disposable script output; none of
#   these paths should be treated as active generation inputs.
#
# Default mode is check-only and never writes. Generation is explicit:
#   scripts/generate_icons.sh --generate [output-directory]
# Generation copies the three canonical SVG compositions and, when a supported
# host rasterizer is available, emits 1024px PNG previews. This is deterministic
# staging/preview output only; it never overwrites an existing file. The checked-
# in scripts/icon_outputs.json is the integrity contract for curated/native
# outputs. Refresh it explicitly after reviewing output changes:
#   scripts/generate_icons.sh --refresh-manifest

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BRAND_DIR="$ROOT_DIR/assets/brand"
MODE=check
OUTPUT_DIR="$ROOT_DIR/.ai/generated-icons"
MANIFEST="$ROOT_DIR/scripts/icon_outputs.json"

usage() {
  printf 'Usage: %s [--check] | [--generate [OUTPUT_DIR]] | [--refresh-manifest]\n' "${0##*/}"
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage
  exit 0
elif [[ ${1:-} == "--check" || -z ${1:-} ]]; then
  MODE=check
elif [[ ${1:-} == "--generate" ]]; then
  MODE=generate
  if [[ -n ${2:-} ]]; then
    OUTPUT_DIR=$2
  fi
  [[ -z ${3:-} ]] || { usage >&2; exit 2; }
elif [[ ${1:-} == "--refresh-manifest" ]]; then
  MODE=refresh_manifest
  [[ -z ${2:-} ]] || { usage >&2; exit 2; }
else
  usage >&2
  exit 2
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
        result.update(paths(f"{platform}/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json"))
        result.update(paths(f"{platform}/Runner/Assets.xcassets/AppIcon.appiconset/*.png"))
        result.update(paths(f"{platform}/Runner.xcodeproj/project.pbxproj"))
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
    if "AppIcon.appiconset/" in path:
        return "Apple fallback catalog output/config"
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
  exit 0
fi

if [[ $MODE == refresh_manifest ]]; then
  exit 0
fi

mkdir -p "$OUTPUT_DIR"
for source in cupola_mark.svg cupola_icon.svg cupola_launcher.svg; do
  target="$OUTPUT_DIR/$source"
  [[ ! -e "$target" ]] || {
    printf 'error: refusing to overwrite %s\n' "$target" >&2
    exit 1
  }
  cp "$BRAND_DIR/$source" "$target"
done

rasterizer=""
if command -v sips >/dev/null 2>&1; then
  rasterizer=sips
elif command -v ffmpeg >/dev/null 2>&1; then
  rasterizer=ffmpeg
fi

if [[ -z $rasterizer ]]; then
  printf 'SVG generation complete; PNG previews skipped (sips/ffmpeg unavailable).\n'
  exit 0
fi

for source in cupola_icon.svg cupola_launcher.svg; do
  target="$OUTPUT_DIR/${source%.svg}.png"
  [[ ! -e "$target" ]] || {
    printf 'error: refusing to overwrite %s\n' "$target" >&2
    exit 1
  }
  if [[ $rasterizer == sips ]]; then
    sips -s format png "$OUTPUT_DIR/$source" --out "$target" >/dev/null
  else
    ffmpeg -loglevel error -y -i "$OUTPUT_DIR/$source" -frames:v 1 -vf scale=1024:1024 "$target"
  fi
done
printf 'Generated canonical SVGs and PNG previews with %s in %s.\n' "$rasterizer" "$OUTPUT_DIR"
