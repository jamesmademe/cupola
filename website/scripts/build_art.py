"""Bake the site's artwork: resized posters and backdrops, a blurred room
picture per title, and the title light read from each poster.

The light follows the app's rule (design/system/light.md) in a simplified
form: a 64 px decode, quantized, clusters too dark or too light dropped, the
most coloured cluster kept and moved to a fixed lightness. The app reads HCT;
this reads HSL, which is close enough for a page lit from a few posters.

Usage: python3 scripts/build_art.py <folder with p-<id>.jpg and b-<id>.jpg>
                                     <folder with s-<still>.png or .jpg>

The stills are frames taken from the films themselves (ffmpeg, full 1080p),
since the posters' backdrops are too small to fill a screen.
Needs Pillow. Writes public/art/, src/og/<id>.jpg (posters for the social
cards, which cannot read WebP) and src/data/light.json.
"""

import colorsys
import json
import sys
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "public" / "art"
# Posters, and the backdrop of the same title where one exists.
IDS = ["bbb", "charge", "cosmos", "sintel", "spring", "sprite", "tos"]
BACKDROPS = {
    "charge": "charge",
    "cosmos": "cosmos",
    "sintel": "sinteldragon",
    "spring": "spring",
    "tos": "tos1",
}
# Frames that lead a screen on their own, lit by themselves, as the app lights
# the Home by the slide in front. Tears of Steel's come from the 1080p film
# (the bridge at 0:35); Singularity's from the Blender
# Studio's 4K "Film frames selection" (shot names 020_0040, 020_0030,
# 060_0010, 090_0010, 100_0040, 080_0050).
STILLS = ["tosbridge", "singopen", "singfind", "singadd", "singget", "singready", "singslide"]
# Singularity has no free poster, so its artwork is cut from a frame (shot
# 020_0060), centred on the critter: (still, horizontal centre of the crop).
STILL_POSTERS = {"singularity": ("singcritter", 0.6)}
OPENING = "singopen"


def still_path(folder: Path, name: str) -> Path:
    for ext in ("png", "jpg"):
        if (folder / f"s-{name}.{ext}").exists():
            return folder / f"s-{name}.{ext}"
    raise FileNotFoundError(folder / f"s-{name}.png")


def light_of(img: Image.Image) -> tuple[str, str]:
    small = img.convert("RGB").resize((64, 64))
    pal = small.quantize(colors=24, method=Image.Quantize.MEDIANCUT)
    palette = pal.getpalette()
    best, best_score = None, -1.0
    for count, idx in pal.getcolors():
        r, g, b = (c / 255 for c in palette[idx * 3 : idx * 3 + 3])
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        if l < 0.12 or l > 0.9:
            continue
        chroma = max(r, g, b) - min(r, g, b)
        score = count * (chroma**1.5)
        if score > best_score:
            best, best_score = (h, s), score
    if best is None or best[1] < 0.12:
        return "#8a8a99", "#8a8a99"
    h, s = best
    light = colorsys.hls_to_rgb(h, 0.66, min(max(s, 0.45), 0.85))
    fill = colorsys.hls_to_rgb(h, 0.78, min(max(s, 0.55), 0.9))
    hexa = lambda c: "#" + "".join(f"{round(v * 255):02x}" for v in c)
    return hexa(light), hexa(fill)


def save(img: Image.Image, path: Path, width: int, quality: int = 80) -> None:
    h = round(img.height * width / img.width)
    img.convert("RGB").resize((width, h), Image.Resampling.LANCZOS).save(
        path, "WEBP", quality=quality, method=6
    )


def main(src: Path, stills: Path) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    lights = {}
    for i in IDS:
        poster = Image.open(src / f"p-{i}.jpg")
        save(poster, OUT / f"{i}-poster.webp", 342)
        save(poster, OUT / f"{i}-poster@2x.webp", 500, 76)
        og = poster.convert("RGB")
        og.resize((300, round(og.height * 300 / og.width)), Image.Resampling.LANCZOS).save(
            ROOT / "src" / "og" / f"{i}.jpg", "JPEG", quality=82, optimize=True
        )
        if i in BACKDROPS:
            backdrop = Image.open(src / f"b-{BACKDROPS[i]}.jpg")
            save(backdrop, OUT / f"{i}-backdrop.webp", 1280, 74)
            save(backdrop, OUT / f"{i}-backdrop-s.webp", 640, 74)
        # The room picture: square crop, blurred, saturated, kept small.
        side = min(poster.size)
        top = (poster.height - side) // 2
        sq = poster.crop((0, top, side, top + side)).convert("RGB").resize((64, 64))
        sq = sq.filter(ImageFilter.GaussianBlur(7))
        sq = ImageEnhance.Color(sq).enhance(2.2)
        sq.save(OUT / f"{i}-room.webp", "WEBP", quality=70)
        light, fill = light_of(poster)
        lights[i] = {"light": light, "fill": fill}
    for name, (file, centre) in STILL_POSTERS.items():
        still = Image.open(still_path(stills, file)).convert("RGB")
        w = round(still.height * 2 / 3)
        left = min(max(round(still.width * centre - w / 2), 0), still.width - w)
        poster = still.crop((left, 0, left + w, still.height))
        save(poster, OUT / f"{name}-poster.webp", 342)
        save(poster, OUT / f"{name}-poster@2x.webp", 500, 76)
        poster.resize((300, 450), Image.Resampling.LANCZOS).save(
            ROOT / "src" / "og" / f"{name}.jpg", "JPEG", quality=82, optimize=True
        )
        sq = poster.crop((0, (poster.height - w) // 2, w, (poster.height + w) // 2)).resize((64, 64))
        sq = ImageEnhance.Color(sq.filter(ImageFilter.GaussianBlur(7))).enhance(2.2)
        sq.save(OUT / f"{name}-room.webp", "WEBP", quality=70)
        light, fill = light_of(poster)
        lights[name] = {"light": light, "fill": fill}
    for name in STILLS:
        still = Image.open(still_path(stills, name))
        # The opening fills a wide screen, so it keeps more of a 4K source.
        save(still, OUT / f"{name}-backdrop.webp", 2560 if name == OPENING and still.width >= 2560 else 1920, 80)
        save(still, OUT / f"{name}-backdrop-s.webp", 640, 76)
        side = min(still.size)
        left = (still.width - side) // 2
        sq = still.crop((left, 0, left + side, side)).convert("RGB").resize((64, 64))
        sq = ImageEnhance.Color(sq.filter(ImageFilter.GaussianBlur(7))).enhance(2.2)
        sq.save(OUT / f"{name}-room.webp", "WEBP", quality=70)
        light, fill = light_of(still)
        lights[name] = {"light": light, "fill": fill}
    (ROOT / "src" / "data" / "light.json").write_text(json.dumps(lights, indent=2) + "\n")
    print(json.dumps(lights, indent=2))


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
