#!/usr/bin/env python3
"""Builds a browsable page of the design system: guidelines, catalog, motion.

For every card listed in design/system/components/README.md it shows the
card's README next to the catalog sheets the real widget renders into
build/design_catalog/<Card>/ (phone and desktop, dark and light). The animated
cards under design/system/motion/ play in frames over the same ground the app
paints: the tokens from design/system/tokens.json as CSS custom properties,
the bundled fonts and motion/motion.{css,js}.

    python3 tool/design_system/gallery.py           # writes build/design_system/
    python3 tool/design_system/gallery.py --render  # renders the catalog first
    python3 tool/design_system/gallery.py --serve   # and serves it on localhost

The output is a build artefact and is never committed.
"""

from __future__ import annotations

import argparse
import functools
import html
import http.server
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from tokens_css import tokens_css

ROOT = Path(__file__).resolve().parents[2]
SYSTEM = ROOT / "design" / "system"
CATALOG = ROOT / "build" / "design_catalog"
OUT = ROOT / "build" / "design_system"

ARTWORK = {
    "__POSTER__": SYSTEM / "assets" / "Imagery" / "poster.jpg",
    "__BACKDROP__": SYSTEM / "assets" / "Imagery" / "backdrop.jpg",
}
FONTS = {
    "Bricolage Grotesque": ROOT / "assets" / "fonts" / "BricolageGrotesque.ttf",
    "Onest": ROOT / "assets" / "fonts" / "Onest.ttf",
    "Geist Mono": ROOT / "assets" / "fonts" / "GeistMono.ttf",
    "CupolaServices": ROOT / "assets" / "fonts" / "CupolaServices.otf",
}
SHEETS = [(p, t) for p in ("phone", "desktop") for t in ("dark", "light")]


# --- Markdown: the subset the READMEs use -----------------------------------

def _inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![*\w])\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def markdown(source: str) -> str:
    out: list[str] = []
    lines = source.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            block = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(html.escape(lines[i]))
                i += 1
            out.append("<pre><code>" + "\n".join(block) + "</code></pre>")
            i += 1
            continue
        heading = re.match(r"(#{1,4})\s+(.*)", line)
        if heading:
            level = len(heading.group(1)) + 1
            out.append(f"<h{level}>{_inline(heading.group(2))}</h{level}>")
            i += 1
            continue
        if line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            head, *body = rows
            out.append(
                "<table><tr>"
                + "".join(f"<th>{_inline(c)}</th>" for c in head)
                + "</tr>"
                + "".join(
                    "<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in row) + "</tr>"
                    for row in body
                )
                + "</table>"
            )
            continue
        if re.match(r"\s*([-*]|\d+\.)\s", line):
            ordered = bool(re.match(r"\s*\d+\.", line))
            items = []
            while i < len(lines) and (
                re.match(r"\s*([-*]|\d+\.)\s", lines[i])
                or (lines[i].startswith("  ") and lines[i].strip())
            ):
                if re.match(r"\s*([-*]|\d+\.)\s", lines[i]):
                    items.append(re.sub(r"\s*([-*]|\d+\.)\s", "", lines[i], count=1))
                else:
                    items[-1] += " " + lines[i].strip()
                i += 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{_inline(x)}</li>" for x in items) + f"</{tag}>")
            continue
        if not line.strip():
            i += 1
            continue
        para = []
        while i < len(lines) and lines[i].strip() and not re.match(r"(#|\||```|\s*([-*]|\d+\.)\s)", lines[i]):
            para.append(lines[i])
            i += 1
        out.append(f"<p>{_inline(' '.join(para))}</p>")
    return "\n".join(out)


# --- The page ----------------------------------------------------------------

def card_index() -> list[tuple[str, str]]:
    """(group, card) from the table in components/README.md, in its order."""
    index = (SYSTEM / "components" / "README.md").read_text()
    rows = []
    for line in index.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and re.fullmatch(r"\[[A-Z][A-Za-z]+\]\(.*\)", cells[1]):
            rows.append((cells[0], re.sub(r"\[([^\]]+)\].*", r"\1", cells[1])))
    return rows


def build() -> Path:
    if OUT.exists():
        shutil.rmtree(OUT)
    for sub in ("fonts", "imagery", "catalog", "motion"):
        (OUT / sub).mkdir(parents=True)

    sections, nav, missing = [], [], []
    book = (SYSTEM / "README.md").read_text()
    # The brand book reads by section: the files beside it that it links, in
    # the order it links them, each a section of its own.
    beside = list(dict.fromkeys(re.findall(r"\]\(([a-z][\w-]*)\.md(?:#[\w-]*)?\)", book)))

    def local(page: str) -> str:
        page = re.sub(r'href="README\.md(?:#[\w-]*)?"', 'href="#brand-book"', page)
        return re.sub(r'href="([a-z][\w-]*)\.md(?:#[\w-]*)?"', r'href="#guide-\1"', page)

    sections.append(f'<section id="brand-book" class="doc">{local(markdown(book))}</section>')
    nav.append('<li class="group">Guidelines</li><li><a href="#brand-book">Brand book</a></li>')
    for stem in beside:
        source = (SYSTEM / f"{stem}.md").read_text()
        title = re.search(r"^# (.+)$", source, re.M)
        label = title.group(1) if title else stem
        sections.append(f'<section id="guide-{stem}" class="doc">{local(markdown(source))}</section>')
        nav.append(f'<li><a href="#guide-{stem}">{html.escape(label)}</a></li>')

    group = None
    for card_group, card in card_index():
        if card_group != group:
            group = card_group
            nav.append(f'<li class="group">{html.escape(group)}</li>')
        nav.append(f'<li><a href="#{card}">{card}</a></li>')
        readme = SYSTEM / "components" / card / "README.md"
        sheets = []
        for platform, theme in SHEETS:
            png = CATALOG / card / f"{platform}.{theme}.png"
            if png.exists():
                target = OUT / "catalog" / card / png.name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(png, target)
                sheets.append(
                    f'<figure><figcaption>{platform} · {theme}</figcaption>'
                    f'<img loading="lazy" src="catalog/{card}/{png.name}" alt="{card}, {platform}, {theme}"></figure>'
                )
        if not sheets:
            missing.append(card)
            sheets.append('<p class="missing">Not rendered yet: run with <code>--render</code>.</p>')
        sections.append(
            f'<section id="{card}"><div class="doc">{markdown(readme.read_text())}</div>'
            f'<div class="sheets">{"".join(sheets)}</div></section>'
        )

    motion = sorted(p.parent.name for p in (SYSTEM / "motion").glob("*/preview.html"))
    nav.append('<li class="group">Motion</li>')
    ground = (
        '<link rel="stylesheet" href="../tokens.css">'
        '<link rel="stylesheet" href="../motion.css">'
        '<script src="../motion.js"></script>'
    )
    for card in motion:
        nav.append(f'<li><a href="#{card}">{card}</a></li>')
        source = (SYSTEM / "motion" / card / "preview.html").read_text()
        marker = re.match(r"<!-- @dsCard(.*?)-->", source)
        height = int(re.search(r"height=(\d+)", marker.group(1)).group(1)) if marker else 320
        for key, path in ARTWORK.items():
            source = source.replace(key, f"../imagery/{path.name}")
        frames = []
        for theme in ("dark", "light"):
            document = re.sub(
                r"<html([^>]*)>", lambda m: f'<html{m.group(1)} data-theme="{theme}">', source, count=1
            ).replace("<head>", "<head>" + ground, 1)
            (OUT / "motion" / f"{card}.{theme}.html").write_text(document)
            frames.append(
                f'<figure><figcaption>{theme}</figcaption>'
                f'<iframe loading="lazy" style="height:{height}px" src="motion/{card}.{theme}.html"></iframe></figure>'
            )
        readme = SYSTEM / "motion" / card / "README.md"
        sections.append(
            f'<section id="{card}"><div class="doc">{markdown(readme.read_text())}</div>'
            f'<div class="sheets">{"".join(frames)}</div></section>'
        )

    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Cupola design system</title>
<style>
  body {{ margin: 0; font: 14px/1.5 system-ui, sans-serif; background: #e5e7eb; color: #111827; }}
  nav {{ position: fixed; inset: 0 auto 0 0; width: 230px; overflow: auto; background: #f9fafb; padding: 16px; box-sizing: border-box; border-right: 1px solid #d1d5db; }}
  nav ul {{ list-style: none; margin: 0; padding: 0; }}
  nav li.group {{ margin-top: 12px; font-weight: 600; color: #4b5563; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }}
  main {{ margin-left: 230px; padding: 24px; }}
  section {{ background: #fff; border-radius: 12px; padding: 20px 24px; margin-bottom: 24px; }}
  .doc {{ max-width: 860px; }}
  .doc h2 {{ margin-top: 0; }}
  code {{ background: #f3f4f6; padding: 1px 4px; border-radius: 4px; font-size: 12.5px; }}
  table {{ border-collapse: collapse; margin: 8px 0; }}
  td, th {{ border: 1px solid #e5e7eb; padding: 4px 8px; text-align: left; vertical-align: top; }}
  .sheets {{ display: grid; gap: 12px; margin-top: 16px; }}
  figure {{ margin: 0; }}
  figcaption {{ font-size: 12px; color: #6b7280; margin-bottom: 4px; }}
  .sheets img {{ max-width: 100%; border: 1px solid #e5e7eb; border-radius: 8px; }}
  iframe {{ width: 960px; max-width: 100%; border: 0; display: block; border-radius: 8px; }}
  .missing {{ color: #b45309; }}
  @media (max-width: 900px) {{
    nav {{ position: static; width: auto; border-right: 0; border-bottom: 1px solid #d1d5db; }}
    main {{ margin-left: 0; padding: 16px; }}
  }}
</style></head>
<body><nav><ul>{''.join(nav)}</ul></nav><main>{''.join(sections)}</main></body></html>
"""
    for font in FONTS.values():
        shutil.copy(font, OUT / "fonts" / font.name)
    for path in ARTWORK.values():
        shutil.copy(path, OUT / "imagery" / path.name)
    (OUT / "tokens.css").write_text(tokens_css(
        json.loads((SYSTEM / "tokens.json").read_text()),
        lambda font: f"fonts/{FONTS[font['family']].name}" if font["family"] in FONTS else None,
    ))
    shutil.copy(SYSTEM / "motion" / "motion.css", OUT / "motion.css")
    shutil.copy(SYSTEM / "motion" / "motion.js", OUT / "motion.js")
    (OUT / "index.html").write_text(page)
    if missing:
        print(f"Not rendered: {', '.join(missing)} (run with --render)")
    return OUT / "index.html"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--render", action="store_true", help="render the design catalog first")
    parser.add_argument("--serve", action="store_true", help="serve the page on localhost")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    if args.render:
        result = subprocess.run(
            ["flutter", "test", "--tags", "catalog", "--run-skipped", "test/design_catalog"],
            cwd=ROOT,
        )
        if result.returncode != 0:
            return result.returncode
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
