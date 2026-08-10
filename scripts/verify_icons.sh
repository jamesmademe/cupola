#!/usr/bin/env bash
set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export ROOT_DIR

if ! bash "$ROOT_DIR/scripts/generate_icons.sh" --check; then
  printf 'FAIL: icon generator manifest/path/hash check failed\n' >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'FAIL: python3 is required for icon verification\n' >&2
  exit 1
fi

python3 - <<'PY'
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(os.environ["ROOT_DIR"])
failures = []

def fail(message):
    failures.append(message)
    print("FAIL: " + message)

def ok(message):
    print("PASS: " + message)

def skip(message):
    print("SKIP: " + message)

def require(path, description=None):
    path = root / path
    if not path.is_file():
        fail("missing " + (description or str(path.relative_to(root))))
        return None
    return path

def png_size(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        raise ValueError("not a PNG")
    return struct.unpack(">II", data[16:24])

def check_png(path, expected=None):
    if path is None:
        return
    try:
        size = png_size(path)
    except (OSError, ValueError) as exc:
        fail(f"{path.relative_to(root)}: {exc}")
        return
    if expected and size != expected:
        fail(f"{path.relative_to(root)}: expected {expected[0]}x{expected[1]}, got {size[0]}x{size[1]}")

def decode_png(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    position = 8
    idat = bytearray()
    width = height = depth = color_type = None
    while position < len(data):
        length = struct.unpack_from(">I", data, position)[0]
        kind = data[position + 4:position + 8]
        chunk = data[position + 8:position + 8 + length]
        position += length + 12
        if kind == b"IHDR":
            width, height, depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or color_type not in (2, 6) or compression or filtering or interlace:
                raise ValueError("unsupported PNG format")
        elif kind == b"IDAT":
            idat.extend(chunk)
        elif kind == b"IEND":
            break
    if width is None or height is None:
        raise ValueError("PNG has no IHDR")
    raw = zlib.decompress(idat)
    channels = 4 if color_type == 6 else 3
    stride = width * channels
    rows = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        row = bytearray(raw[offset:offset + stride])
        offset += stride
        for index in range(stride):
            left = row[index - channels] if index >= channels else 0
            up = previous[index]
            up_left = previous[index - channels] if index >= channels else 0
            if filter_type == 1:
                row[index] = (row[index] + left) & 255
            elif filter_type == 2:
                row[index] = (row[index] + up) & 255
            elif filter_type == 3:
                row[index] = (row[index] + ((left + up) // 2)) & 255
            elif filter_type == 4:
                estimate = left + up - up_left
                distances = (abs(estimate - left), abs(estimate - up), abs(estimate - up_left))
                predictor = (left, up, up_left)[distances.index(min(distances))]
                row[index] = (row[index] + predictor) & 255
            elif filter_type != 0:
                raise ValueError("unsupported PNG filter")
        rows.append(row)
        previous = row
    return width, height, color_type, rows, channels

def check_monochrome(path):
    if path is None:
        return
    temporary = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
    temporary.close()
    try:
        result = subprocess.run(
            ["dwebp", "-quiet", str(path), "-o", temporary.name],
            capture_output=True,
            text=True,
        )
        if result.returncode:
            raise ValueError(result.stderr.strip() or "dwebp failed")
        width, height, color_type, rows, channels = decode_png(Path(temporary.name))
        if color_type != 6:
            raise ValueError("decoded image has no alpha channel")
        pixels = [tuple(row[index:index + channels]) for row in rows for index in range(0, width * channels, channels)]
        visible = [pixel for pixel in pixels if pixel[3] > 0]
        transparent = [pixel for pixel in pixels if pixel[3] == 0]
        if not visible:
            raise ValueError("has no visible pixels")
        if not transparent:
            raise ValueError("has no transparent background")
        if len({pixel[:3] for pixel in visible}) != 1:
            raise ValueError("visible pixels are not a single color")
    except (OSError, ValueError, struct.error, zlib.error) as exc:
        fail(f"{path.relative_to(root)}: monochrome content invalid ({exc})")
    finally:
        Path(temporary.name).unlink(missing_ok=True)

def check_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        fail(f"{path.relative_to(root)}: invalid JSON ({exc})")
        return None

def resolve_resource(value):
    match = re.fullmatch(r"@(drawable|mipmap)/([A-Za-z0-9_]+)", value or "")
    if not match:
        return None
    kind, name = match.groups()
    candidates = sorted((root / "android/app/src/main/res").glob(f"{kind}-*/{name}.*"))
    candidates += sorted((root / "android/app/src/main/res").glob(f"{kind}/{name}.*"))
    return candidates[0] if candidates else None

# Canonical SVG source policy: exactly the three declared compositions, with
# the mark as the sole geometry source and no generated SVG family.
brand = root / "assets/brand"
for name in ("cupola_mark.svg", "cupola_icon.svg", "cupola_launcher.svg"):
    path = require(f"assets/brand/{name}")
    if path:
        try:
            svg = ET.parse(path).getroot()
            if svg.tag != "{http://www.w3.org/2000/svg}svg" or svg.get("viewBox") != "0 0 1024 1024":
                fail(f"{path.relative_to(root)}: must be SVG with viewBox 0 0 1024 1024")
        except (OSError, ET.ParseError) as exc:
            fail(f"{path.relative_to(root)}: invalid SVG ({exc})")
for path in root.glob("**/*.svg"):
    if any(part.startswith(".") for part in path.parts):
        continue  # dot-directories are untracked build output
    if path.parent != brand:
        fail(f"unexpected SVG geometry source: {path.relative_to(root)}")
ok("canonical SVG source policy")

# Android adaptive resources, references, palette parity, and all density
# families. WebP is accepted because Android launcher exports use it here.
manifest = require("android/app/src/main/AndroidManifest.xml")
if manifest:
    text = manifest.read_text()
    if 'android:icon="@mipmap/cupola_icon"' not in text or 'android:roundIcon="@mipmap/cupola_icon_round"' not in text:
        fail("Android manifest does not reference both adaptive icons")
for name in ("cupola_icon.xml", "cupola_icon_round.xml"):
    path = require(f"android/app/src/main/res/mipmap-anydpi-v26/{name}")
    if path:
        try:
            tree = ET.parse(path).getroot()
            refs = {child.tag.rsplit("}", 1)[-1]: child.attrib.get("{http://schemas.android.com/apk/res/android}drawable") for child in tree}
            for part in ("background", "foreground", "monochrome"):
                if part not in refs or not resolve_resource(refs[part]):
                    fail(f"{path.relative_to(root)}: missing or unresolved {part} resource")
        except (OSError, ET.ParseError) as exc:
            fail(f"{path.relative_to(root)}: invalid XML ({exc})")
light = require("android/app/src/main/res/drawable/cupola_icon_bg_gradient.xml")
night = require("android/app/src/main/res/drawable-night/cupola_icon_bg_gradient.xml")
if light and night:
    colors = lambda p: re.findall(r'android:(?:startColor|centerColor|endColor)="([#A-Fa-f0-9]+)"', p.read_text())
    if not colors(light) or not colors(night):
        fail("Android icon background gradients are missing colour stops")
    elif colors(light) == colors(night):
        fail("Android light/night icon backgrounds are identical; the theme split regressed")
for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    directory = root / "android/app/src/main/res" / f"mipmap-{density}"
    for suffix in ("", "_round", "_foreground", "_monochrome"):
        matches = list(directory.glob(f"cupola_icon{suffix}.*"))
        if not matches:
            fail(f"Android missing {density} cupola_icon{suffix} output")
        for path in matches:
            if path.suffix.lower() == ".png":
                check_png(path)
for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    for suffix in ("", "_round", "_foreground"):
        directory = root / "android/app/src/main/res" / f"mipmap-night-{density}"
        if not list(directory.glob(f"cupola_icon{suffix}.*")):
            fail(f"Android missing night-{density} cupola_icon{suffix} output")
if shutil.which("dwebp"):
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        path = root / "android/app/src/main/res" / f"mipmap-{density}/cupola_icon_monochrome.webp"
        check_monochrome(path if path.is_file() else None)
    ok("Android monochrome WebP content")
else:
    skip("Android monochrome content inspection unavailable (dwebp not found)")
ok("Android manifest, adaptive resources, density outputs, and palette")

# Apple active Icon Composer bundles and synchronized fallback catalogs.
for platform in ("ios", "macos"):
    bundle = root / f"{platform}/Runner/cupola_icon.icon"
    data = check_json(bundle / "icon.json") if (bundle / "icon.json").is_file() else None
    if data is None:
        require(f"{platform}/Runner/cupola_icon.icon/icon.json")
    else:
        refs = {layer.get("image-name") for group in data.get("groups", []) for layer in group.get("layers", []) if layer.get("image-name")}
        for image in refs:
            require(f"{platform}/Runner/cupola_icon.icon/Assets/{image}")
        if not {"Light", "Dark"}.issubset({group.get("name") for group in data.get("groups", [])}):
            fail(f"{platform} Icon Composer JSON lacks light/dark groups")
    catalog = root / f"{platform}/Runner/Assets.xcassets/AppIcon.appiconset"
    project = root / f"{platform}/Runner.xcodeproj/project.pbxproj"
    if not project.is_file() or "cupola_icon.icon" not in project.read_text():
        fail(f"{platform} Xcode project does not include active Icon Composer bundle")
    contents = check_json(catalog / "Contents.json") if (catalog / "Contents.json").is_file() else None
    if contents:
        for image in contents.get("images", []):
            filename = image.get("filename")
            path = catalog / filename if filename else None
            if not path or not path.is_file():
                fail(f"{platform} fallback catalog missing {filename or 'filename'}")
            else:
                size = image.get("size", "").split("x")
                expected = (round(float(size[0]) * float(image.get("scale", "1x")[0])), round(float(size[1]) * float(image.get("scale", "1x")[0])))
                check_png(path, expected)
    else:
        require(f"{platform}/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json")
ok("Apple Icon Composer and fallback catalogs")

# Web manifest/index references, purpose semantics, descriptions, and PNGs.
web_manifest = check_json(root / "web/manifest.json")
if web_manifest:
    if not web_manifest.get("description") or "Cupola" not in web_manifest.get("name", ""):
        fail("web manifest needs name and description")
    purposes = {entry.get("purpose") for entry in web_manifest.get("icons", [])}
    if not {"any", "maskable"}.issubset(purposes):
        fail("web manifest must provide any and maskable icon purposes")
    for entry in web_manifest.get("icons", []):
        path = root / "web" / entry.get("src", "")
        check_png(path, tuple(map(int, entry.get("sizes", "0x0").split("x")))) if path.is_file() else fail(f"missing web icon {entry.get('src')}")
index = require("web/index.html")
if index:
    text = index.read_text()
    for ref in ("manifest.json", "icons/Icon-192.png", "favicon-light.png", "favicon.png"):
        if ref not in text:
            fail(f"web/index.html does not reference {ref}")
    if 'meta name="description"' not in text:
        fail("web/index.html lacks description")
for name in ("favicon.png", "favicon-light.png"):
    check_png(require(f"web/{name}"), (32, 32))
ok("web manifest and index references")

# Windows metadata and all ICO directory entries.
rc = require("windows/runner/Runner.rc")
ico = require("windows/runner/resources/app_icon.ico")
if rc:
    text = rc.read_text()
    for token in ('IDI_APP_ICON', 'resources\\\\app_icon.ico', 'ProductName", "Cupola', 'FileDescription", "Cupola'):
        if token not in text:
            fail(f"Runner.rc missing metadata/reference {token}")
if ico:
    data = ico.read_bytes()
    if len(data) < 6 or data[:4] != b"\0\0\1\0":
        fail("Windows icon is not an ICO")
    else:
        count = struct.unpack_from("<H", data, 4)[0]
        required_sizes = {16, 32, 48, 64, 128, 256}
        sizes = set()
        for i in range(count):
            w, h = struct.unpack_from("<BB", data, 6 + i * 16)
            if w == 0: w = 256
            if h == 0: h = 256
            sizes.add((w, h))
            if w != h or w < 16:
                fail(f"Windows ICO entry {i} has invalid dimensions {w}x{h}")
        missing_sizes = sorted(size for size in required_sizes if (size, size) not in sizes)
        if missing_sizes:
            fail(f"Windows ICO is missing standard sizes: {missing_sizes}")
ok("Windows metadata and ICO entries")

# Linux desktop metadata, install wiring, and hicolor PNG dimensions.
desktop = require("linux/runner/cupola.desktop")
cmake = require("linux/CMakeLists.txt")
if desktop:
    text = desktop.read_text()
    if not all(token in text for token in ("Name=Cupola", "Exec=cupola", "Icon=cupola", "Type=Application")):
        fail("Linux desktop metadata is incomplete")
if cmake:
    text = cmake.read_text()
    for token in ("INSTALL_ICON_DIR", "foreach(icon_size 16 32 48 64 128 256)", "runner/icons/hicolor"):
        if token not in text:
            fail(f"Linux CMake install wiring missing {token}")
for size in (16, 32, 48, 64, 128, 256):
    check_png(require(f"linux/runner/icons/hicolor/{size}x{size}/apps/cupola.png"), (size, size))
ok("Linux desktop metadata, CMake wiring, and hicolor outputs")

# The generator is check-only by default; --write is the explicit regeneration
# path and scripts/icons/ holds the geometry every output descends from.
generator = require("scripts/generate_icons.sh")
if generator:
    text = generator.read_text()
    if "MODE=check" not in text or "--check" not in text or "--write" not in text:
        fail("icon generator lacks explicit check/write modes")
for name in ("scripts/icons/masters.py", "scripts/icons/export.py"):
    require(name)
ok("icon generator presence, check mode, and geometry source")

if failures:
    print(f"Icon verification failed: {len(failures)} issue(s).", file=sys.stderr)
    sys.exit(1)
print("Icon verification passed; SKIP lines are unavailable host-only checks, not passes.")
PY
PYTHON_STATUS=$?

if command -v xcrun >/dev/null 2>&1 && xcrun --find actool >/dev/null 2>&1; then
  ACTOOL_DIR=$(mktemp -d)
  ACTOOL_STATUS=0
  for platform in ios macos; do
    mkdir -p "$ACTOOL_DIR/$platform"
    mkdir -p "$ACTOOL_DIR/$platform/compiled"
    if [[ $platform == ios ]]; then
      ACTOOL_PLATFORM=iphoneos
      ACTOOL_MINIMUM=13.0
    else
      ACTOOL_PLATFORM=macosx
      ACTOOL_MINIMUM=11.0
    fi
    if ! xcrun actool --warnings --errors \
      --platform "$ACTOOL_PLATFORM" \
      --minimum-deployment-target "$ACTOOL_MINIMUM" \
      --app-icon cupola_icon \
      --output-partial-info-plist "$ACTOOL_DIR/$platform/partial-info.plist" \
      --compile "$ACTOOL_DIR/$platform/compiled" \
      "$ROOT_DIR/$platform/Runner/cupola_icon.icon" \
      "$ROOT_DIR/$platform/Runner/Assets.xcassets"; then
      printf 'FAIL: actool validation failed for %s catalogs\n' "$platform" >&2
      ACTOOL_STATUS=1
    fi
  done
  rm -rf "$ACTOOL_DIR"
  if [[ $ACTOOL_STATUS -eq 0 ]]; then
    printf 'PASS: actool compiled iOS and macOS Icon Composer and fallback catalogs\n'
  fi
else
  printf 'SKIP: xcrun/actool unavailable; Apple catalog compilation not inspected\n'
fi

if [[ ${ACTOOL_STATUS:-0} -ne 0 ]]; then
  exit 1
fi
exit "$PYTHON_STATUS"
