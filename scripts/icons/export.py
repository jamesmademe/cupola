#!/usr/bin/env python3
"""Render the icon masters into every platform target, in place.

Driven by `scripts/generate_icons.sh --write`; not meant to be run bare. All
geometry and colour live in `masters.py`; this file only decides which master
goes where, at what size, and with which alpha policy.

Appearance mapping
------------------
Android switches with the system theme: the unqualified `mipmap-*` and
`drawable/` resources carry the light appearance, the `-night` ones carry the
dark. Both the adaptive background and its foreground have a night twin, because
switching only the background would leave a dark structure sitting on a pale
ground. Note the fallback: a launcher that does not resolve `-night` in its own
configuration shows the unqualified resource, so dark-theme users on such a
launcher get the light icon rather than a broken one.

Apple switches through the Icon Composer bundle's own light and dark layer
groups, and neither platform has an `.appiconset` any more: actool reads none once
the target's app icon is an Icon Composer bundle, so both were dead weight that
read as live. What each platform falls back to on a system too old to recompose a
`.icon` differs. macOS reads `cupola_icon_legacy.icns`, which this file writes:
see `write_icns`. iOS reads two PNGs actool derives from the `.icon` itself,
naming them in the Info.plist; nothing here can add to that set, so iOS keeps a
thinner fallback than macOS by Apple's choice rather than ours.

Those fallbacks have no appearance channel, so they carry the dark appearance,
which is the product's committed identity.

Web follows `index.html`, which serves `favicon-light.png` under
`prefers-color-scheme: light` and `favicon.png` otherwise.

Windows and Linux have no appearance channel; both take the dark appearance.
"""

from __future__ import annotations

import argparse
import io
import struct
import subprocess
import sys
from pathlib import Path

from PIL import Image

RESVG = ["npx", "--yes", "@resvg/resvg-js-cli"]

# Below this the cloud passes only add mud, so the simplified twin takes over.
SIMPLE_BELOW = 64

# The mark on the launch screen, in points (dp on Android): the same size on
# every platform, centred on the room's ground.
LAUNCH_POINTS = 112

# Android 12's splash icon is a 288dp square the system draws itself. A drawable
# that only insets the mark (`<inset>`) is drawn as nothing there, so the
# padding is in the picture: the mark at LAUNCH_POINTS on a clear 288dp canvas.
SPLASH_POINTS = 288
LAUNCH_SCALES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# The `.icns` element types macOS reads as PNG, paired with the pixel size each
# one declares. Both the 1x and the @2x code for a point size are present: the
# retina codes are what a modern Dock asks for, the 1x codes are what a stray
# pre-retina context and some third-party icon readers ask for.
MACOS_ICNS = {
    "icp4": 16,
    "ic11": 32,
    "icp5": 32,
    "ic12": 64,
    "ic07": 128,
    "ic13": 256,
    "ic08": 256,
    "ic14": 512,
    "ic09": 512,
    "ic10": 1024,
}

APPLE_LAYERS = {
    "cupola-core-light.png": "layer-core-light",
    "cupola-core-dark.png": "layer-core-dark",
    "cupola-panes-light.png": "layer-panes-light",
    "cupola-panes-dark.png": "layer-panes-dark",
    "cupola-frame-light.png": "layer-frame-light",
    "cupola-frame-dark.png": "layer-frame-dark",
    "cupola_fg.png": "android-fg-dark",
    "preview-light-ground.png": "preview-ground",
}

# Transparency is load-bearing only where something else composites the asset:
# Apple's layer groups, Android's adaptive foreground and themed icon, and the
# in-app mark that sits over the app's own surface. Everywhere else the alpha
# channel is dead weight, and on Apple's 1024 marketing slot it is a submission
# blocker.
ALPHA_KEEPERS = (
    "cupola_icon.icon/Assets/",
    "cupola_icon_foreground.webp",
    "cupola_icon_monochrome.webp",
    "assets/brand/cupola_mark.png",
    "LaunchImage.imageset/",
    "/launch_mark.png",
    "/launch_splash_mark.png",
)

# Icon Composer derives the icon's ground from this fill rather than from a
# layer, so the light group needs the light appearance's body colour.
ICON_JSON_LIGHT_FILL_WAS = "display-p3:0.27059,0.28235,0.68627,1.00000"
ICON_JSON_LIGHT_FILL_NOW = "display-p3:0.87451,0.89412,0.93725,1.00000"


class Exporter:
    def __init__(self, repo: Path, masters: Path):
        self.repo = repo
        self.masters = masters
        self.cache: dict[str, Image.Image] = {}
        self.written: list[str] = []

    # ---------------------------------------------------------------- render
    def master(self, name: str) -> Image.Image:
        if name not in self.cache:
            png = self.masters / f"{name}.png"
            if not png.exists():
                self._run(RESVG + ["--fit-width", "1024", str(self.masters / f"{name}.svg"), str(png)])
            self.cache[name] = Image.open(png).convert("RGBA")
        return self.cache[name]

    @staticmethod
    def _run(cmd):
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise SystemExit(
                f"error: {' '.join(map(str, cmd))}\n{result.stderr[-800:]}\n"
                "hint: the rasteriser needs node + npx on PATH"
            )

    def emit(self, master: str, size: int, rel: str):
        dest = self.repo / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        image = self.master(master)
        if size != 1024:
            image = image.resize((size, size), Image.LANCZOS)
        if not any(k in rel for k in ALPHA_KEEPERS):
            ground = Image.new("RGB", image.size, (5, 6, 11))
            ground.paste(image, mask=image.split()[3])
            image = ground
        if rel.endswith(".webp"):
            image.save(dest, "WEBP", quality=94, method=6)
        else:
            image.save(dest, "PNG", optimize=True)
        self.written.append(rel)

    def write_ico(self, rel: str, entries):
        """Multi-image ICO with embedded PNGs, one entry per shell context."""
        blobs = []
        for size in entries:
            image = self.master(self.full(size))
            if size != 1024:
                image = image.resize((size, size), Image.LANCZOS)
            ground = Image.new("RGB", image.size, (5, 6, 11))
            ground.paste(image, mask=image.split()[3])
            buffer = io.BytesIO()
            ground.save(buffer, "PNG", optimize=True)
            blobs.append((size, buffer.getvalue()))

        offset = 6 + 16 * len(blobs)
        directory = b""
        payload = b""
        for size, blob in blobs:
            dimension = 0 if size >= 256 else size  # 0 means 256 in the ICO header
            directory += struct.pack("<BBBBHHII", dimension, dimension, 0, 0, 1, 32, len(blob), offset)
            offset += len(blob)
            payload += blob

        dest = self.repo / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(struct.pack("<HHH", 0, 1, len(blobs)) + directory + payload)
        self.written.append(rel)

    def write_icns(self, rel: str):
        """The macOS fallback icon, for every system older than the Icon Composer era.

        macOS 26 renders `cupola_icon.icon` out of the compiled asset catalogue.
        Nothing older can read that asset, so it falls back to the `.icns` named by
        CFBundleIconFile, and the one actool derives from a `.icon` carries four
        elements only (16, 16@2x, 128, 128@2x), leaving a Dock on macOS 15 to
        upscale a 256px image into a 512px slot. This is the full set, and the
        target's `Complete the legacy .icns` build phase drops it over actool's.

        An `.appiconset` cannot do this job: actool ignores one entirely once the
        target's app icon is an Icon Composer bundle.

        Alpha is load-bearing here: the shape's corners are the transparency.
        """
        payload = b""
        for code, size in MACOS_ICNS.items():
            master = "icon-macos-simple" if size < SIMPLE_BELOW else "icon-macos"
            image = self.master(master)
            if size != 1024:
                image = image.resize((size, size), Image.LANCZOS)
            buffer = io.BytesIO()
            image.save(buffer, "PNG", optimize=True)
            blob = buffer.getvalue()
            payload += code.encode("ascii") + struct.pack(">I", len(blob) + 8) + blob

        dest = self.repo / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
        self.written.append(rel)

    def emit_centred(self, master: str, inner: int, outer: int, rel: str):
        """[master] at [inner] pixels, centred on a clear [outer] square."""
        dest = self.repo / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        mark = self.master(master).resize((inner, inner), Image.LANCZOS)
        canvas = Image.new("RGBA", (outer, outer), (0, 0, 0, 0))
        offset = (outer - inner) // 2
        canvas.paste(mark, (offset, offset), mark)
        canvas.save(dest, "PNG", optimize=True)
        self.written.append(rel)

    def write_text(self, rel: str, text: str):
        dest = self.repo / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(text, encoding="utf-8")
        self.written.append(rel)

    # ------------------------------------------------------------- the plan
    @staticmethod
    def full(size: int, appearance: str = "dark") -> str:
        """The full composition, dropping to the simplified twin when small."""
        if size < SIMPLE_BELOW:
            return "icon-simple" if appearance == "dark" else "icon-simple-light"
        return "icon-dark" if appearance == "dark" else "icon-light"

    def apple(self):
        for platform in ("ios", "macos"):
            for name, master in APPLE_LAYERS.items():
                self.emit(master, 1024, f"{platform}/Runner/cupola_icon.icon/Assets/{name}")
            self.patch_icon_json(platform)

        self.write_icns("macos/Runner/cupola_icon_legacy.icns")

    def patch_icon_json(self, platform: str):
        """Point the light group's ground at the light appearance's body colour.

        A targeted substitution rather than a JSON round-trip: Icon Composer owns
        this file's formatting, and reformatting it would bury the one real change
        under three hundred lines of noise.
        """
        rel = f"{platform}/Runner/cupola_icon.icon/icon.json"
        path = self.repo / rel
        text = path.read_text(encoding="utf-8")
        if ICON_JSON_LIGHT_FILL_NOW in text:
            return
        if ICON_JSON_LIGHT_FILL_WAS not in text:
            raise SystemExit(
                f"error: {rel} no longer contains the expected light fill "
                f"{ICON_JSON_LIGHT_FILL_WAS}; refusing to guess"
            )
        path.write_text(text.replace(ICON_JSON_LIGHT_FILL_WAS, ICON_JSON_LIGHT_FILL_NOW), "utf-8")
        self.written.append(rel)

    def android(self, ground_xml):
        res = "android/app/src/main/res"
        for density, size in DENSITIES.items():
            day = self.full(size, "light")
            night = self.full(size, "dark")
            self.emit(day, size, f"{res}/mipmap-{density}/cupola_icon.webp")
            self.emit(day, size, f"{res}/mipmap-{density}/cupola_icon_round.webp")
            self.emit("android-fg-light", size, f"{res}/mipmap-{density}/cupola_icon_foreground.webp")
            self.emit("mono", size, f"{res}/mipmap-{density}/cupola_icon_monochrome.webp")

            self.emit(night, size, f"{res}/mipmap-night-{density}/cupola_icon.webp")
            self.emit(night, size, f"{res}/mipmap-night-{density}/cupola_icon_round.webp")
            self.emit(
                "android-fg-dark", size, f"{res}/mipmap-night-{density}/cupola_icon_foreground.webp"
            )

        self.write_text(f"{res}/drawable/cupola_icon_bg_gradient.xml", ground_xml("light"))
        self.write_text(f"{res}/drawable-night/cupola_icon_bg_gradient.xml", ground_xml("dark"))

        # Play Console listing art; not a build input, but it belongs to the mark.
        self.emit("icon-dark", 512, "android/app/src/main/cupola_icon-playstore.png")

    def desktop_and_web(self):
        for size in (16, 32, 48, 64, 128, 256):
            self.emit(self.full(size), size, f"linux/runner/icons/hicolor/{size}x{size}/apps/cupola.png")

        self.emit("icon-simple", 32, "web/favicon.png")
        self.emit("icon-light", 32, "web/favicon-light.png")
        self.emit("icon-dark", 192, "web/icons/Icon-192.png")
        self.emit("icon-dark", 512, "web/icons/Icon-512.png")
        self.emit("maskable", 192, "web/icons/Icon-maskable-192.png")
        self.emit("maskable", 512, "web/icons/Icon-maskable-512.png")

        self.write_ico("windows/runner/resources/app_icon.ico", (16, 32, 48, 64, 128, 256))

    def launch(self):
        """The mark on the launch screen: transparent, since the storyboard and
        the window background lay it over the room's ground."""
        imageset = "ios/Runner/Assets.xcassets/LaunchImage.imageset"
        for scale in (1, 2, 3):
            suffix = "" if scale == 1 else f"@{scale}x"
            self.emit("mark", LAUNCH_POINTS * scale, f"{imageset}/LaunchImage{suffix}.png")
        res = "android/app/src/main/res"
        for density, scale in LAUNCH_SCALES.items():
            self.emit("mark", round(LAUNCH_POINTS * scale), f"{res}/drawable-{density}/launch_mark.png")
            self.emit_centred(
                "mark",
                round(LAUNCH_POINTS * scale),
                round(SPLASH_POINTS * scale),
                f"{res}/drawable-{density}/launch_splash_mark.png",
            )

    def in_app(self):
        """The mark drawn inside ServiceRing: transparent, over the app surface."""
        self.emit("mark", 1024, "assets/brand/cupola_mark.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--masters", required=True)
    args = parser.parse_args()

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from masters import android_ground_xml  # noqa: E402

    exporter = Exporter(Path(args.repo), Path(args.masters))
    exporter.apple()
    exporter.android(android_ground_xml)
    exporter.desktop_and_web()
    exporter.launch()
    exporter.in_app()

    print(f"targets: {len(exporter.written)} file scritti")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
