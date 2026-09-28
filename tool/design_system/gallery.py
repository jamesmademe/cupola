#!/usr/bin/env python3
"""Builds a browsable gallery of the design system's component cards.

Every card under design/system/components/<Card>/preview.html is rendered twice,
dark and light, at the 960px width the cards are drawn for, over the same
ground a card expects: the tokens from design/system/tokens.json as CSS custom
properties, the bundled fonts, components/bundle.css and components/bundle.js.

    python3 tool/design_system/gallery.py          # writes build/design_system/
    python3 tool/design_system/gallery.py --serve  # and serves it on localhost

The output is a build artefact and is never committed. Edit the cards, the
tokens (design/tokens/, then run the token generator) or bundle.css, and build
again.
"""

from __future__ import annotations

import argparse
import functools
import html
import http.server
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYSTEM = ROOT / "design" / "system"
OUT = ROOT / "build" / "design_system"

# Artwork placeholders a card may use; the files live beside the cards.
ARTWORK = {
    "__POSTER__": SYSTEM / "assets" / "Imagery" / "poster.jpg",
    "__BACKDROP__": SYSTEM / "assets" / "Imagery" / "backdrop.jpg",
}

# Font files are the app's own; the gallery copies them next to its page.
FONTS = {
    "Inter": ROOT / "assets" / "fonts" / "Inter.ttf",
    "CupolaServices": ROOT / "assets" / "fonts" / "CupolaServices.otf",
}


def _css_value(value: str) -> str:
    alias = re.fullmatch(r"\{(.+)\}", value)
    return f"var(--{alias.group(1)})" if alias else value


def _per_theme(value, theme: str, first: str) -> str:
    if isinstance(value, str):
        return value
    return value.get(theme, value[first])


def tokens_css(tokens: dict) -> str:
    """The tokens as custom properties: one block per theme, one shared."""
    themes = [t["id"] for t in tokens["color"]["themes"]]
    first = themes[0]
    blocks = []
    for index, theme in enumerate(themes):
        selector = (
            f':root, [data-theme="{theme}"]' if index == 0 else f'[data-theme="{theme}"]'
        )
        props = [
            f"--{t['name']}: {_css_value(_per_theme(t['value'], theme, first))};"
            for t in tokens["color"]["tokens"]
        ]
        props += [
            f"--{t['name']}: {_per_theme(t['value'], theme, first)};"
            for t in tokens.get("shadow", {}).get("tokens", [])
        ]
        blocks.append(f"{selector} {{ {' '.join(props)} }}")

    shared = []
    for family in ("spacing", "radius", "breakpoint"):
        shared += [
            f"--{t['name']}: {t['value']};"
            for t in tokens.get(family, {}).get("tokens", [])
        ]
    for key, stack in tokens["type"]["families"].items():
        shared.append(f"--font-{key}: {stack};")
    blocks.append(f":root {{ {' '.join(shared)} }}")

    for font in tokens["type"]["fonts"]:
        source = FONTS.get(font["family"])
        if source is None:
            continue
        blocks.append(
            "@font-face { "
            f"font-family: \"{font['family']}\"; "
            f"src: url(\"fonts/{source.name}\"); "
            f"font-weight: {font['weight']}; font-style: {font.get('style', 'normal')}; "
            "}"
        )
    return "\n".join(blocks)


def build() -> Path:
    tokens = json.loads((SYSTEM / "tokens.json").read_text())
    components = SYSTEM / "components"
    # Shared by every frame as files beside the page, not inlined into each
    # one: a frame's relative URLs resolve against the gallery's own address.
    ground = (
        '<link rel="stylesheet" href="tokens.css">'
        '<link rel="stylesheet" href="bundle.css">'
        '<script src="bundle.js"></script>'
    )
    artwork = {key: f"imagery/{path.name}" for key, path in ARTWORK.items() if path.exists()}

    cards = sorted(
        path.parent.name for path in components.glob("*/preview.html")
    )
    sections = []
    index = []
    for name in cards:
        source = (components / name / "preview.html").read_text()
        marker = re.match(r"<!-- @dsCard(.*?)-->", source)
        height = int(re.search(r"height=(\d+)", marker.group(1)).group(1)) if marker else 320
        group = re.search(r'group="([^"]+)"', marker.group(1)) if marker else None
        for key, uri in artwork.items():
            source = source.replace(key, uri)
        index.append(
            f'<li><a href="#{name}">{name}</a>'
            f'<span>{html.escape(group.group(1)) if group else ""}</span></li>'
        )
        frames = []
        for theme in ("dark", "light"):
            document = re.sub(
                r"<html([^>]*)>",
                lambda m: f'<html{m.group(1)} data-theme="{theme}">',
                source,
                count=1,
            ).replace("<head>", "<head>" + ground, 1)
            frames.append(
                f'<figure><figcaption>{theme}</figcaption>'
                f'<iframe loading="lazy" style="height:{height}px" '
                f'srcdoc="{html.escape(document)}"></iframe></figure>'
            )
        sections.append(f'<section id="{name}"><h2>{name}</h2>{"".join(frames)}</section>')

    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Cupola design system</title>
<style>
  body {{ margin: 0; font: 14px/1.45 system-ui, sans-serif; background: #6b7280; color: #111827; }}
  nav {{ position: fixed; inset: 0 auto 0 0; width: 220px; overflow: auto; background: #f3f4f6; padding: 16px; box-sizing: border-box; }}
  nav ul {{ list-style: none; margin: 0; padding: 0; }}
  nav li {{ display: flex; justify-content: space-between; gap: 8px; padding: 2px 0; }}
  nav span {{ color: #4b5563; font-size: 12px; }}
  main {{ margin-left: 220px; padding: 16px; }}
  section {{ margin-bottom: 32px; }}
  h2 {{ color: #fff; margin: 0 0 8px; }}
  figure {{ margin: 0 0 8px; }}
  figcaption {{ color: #e5e7eb; font-size: 12px; margin-bottom: 2px; }}
  iframe {{ width: 960px; border: 0; display: block; }}
</style></head>
<body><nav><strong>{len(cards)} cards</strong><ul>{''.join(index)}</ul></nav>
<main>{''.join(sections)}</main></body></html>
"""
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "fonts").mkdir(parents=True)
    (OUT / "imagery").mkdir()
    for font in FONTS.values():
        shutil.copy(font, OUT / "fonts" / font.name)
    for path in ARTWORK.values():
        if path.exists():
            shutil.copy(path, OUT / "imagery" / path.name)
    (OUT / "tokens.css").write_text(tokens_css(tokens))
    shutil.copy(components / "bundle.css", OUT / "bundle.css")
    shutil.copy(components / "bundle.js", OUT / "bundle.js")
    (OUT / "index.html").write_text(page)
    return OUT / "index.html"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--serve", action="store_true", help="serve the gallery on localhost")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    page = build()
    print(f"Wrote {page.relative_to(ROOT)}")
    if args.serve:
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(OUT))
        with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
            print(f"Serving on http://127.0.0.1:{args.port}/ (Ctrl+C to stop)")
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
