#!/usr/bin/env python3
"""Checks the mockup canvas's open boards against the canvas kit.

    python3 tool/design_system/lint_boards.py <folder of .dc.html> \\
        --kit <kit/tokens.css> --canvas <canvas.json> [--all-pages]

A board outside the archive (its page in canvas.json is not `archive`):

- error: a colour written as a literal (`#hex`, `rgb()`, `hsl()`) anywhere
  but in a `--art-*` declaration. The light a title's artwork casts is the
  one colour a token cannot hold, and a board declares it so
  (`--art-glow: #ACA784;`) and paints it through var(--art-glow);
- warning, with the variable to use, when such a literal is a token's value
  (`#f7f6f2 = var(--ink-primary) (dark)`);
- error: no `<link rel="stylesheet" href="kit/tokens.css">` right after the
  board's `support.js` line.

Exit status: 0 clean or warnings only, 1 with an error.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

COLOUR = re.compile(r"#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\([^)]*\)")
ART = re.compile(r"--art-[\w-]+\s*:[^;\"'}]*")
SUPPORT = '<script src="./support.js"></script>'
KIT_LINK = re.compile(r'\s*<link rel="stylesheet" href="kit/tokens\.css">')


def _hex(value: str) -> str | None:
    """A colour as lower #rrggbb[aa], an opaque alpha dropped: #abc, #abcd,
    #aabbcc, #aabbccdd, rgb() and rgba() with 0-255 channels."""
    value = value.lower().strip()
    rgb = re.fullmatch(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)", value)
    if rgb:
        r, g, b = (int(c) for c in rgb.groups()[:3])
        alpha = round(float(rgb.group(4) or 1) * 255)
        value = f"#{r:02x}{g:02x}{b:02x}{alpha:02x}"
    if not re.fullmatch(r"#[0-9a-f]{3,8}", value) or len(value) not in (4, 5, 7, 9):
        return None
    digits = value[1:]
    if len(digits) in (3, 4):
        digits = "".join(c * 2 for c in digits)
    if len(digits) == 8 and digits.endswith("ff"):
        digits = digits[:6]
    return f"#{digits}"


def kit_values(css: str) -> dict[str, list[str]]:
    """Literal colour → the variables (and theme) that hold it."""
    found: dict[str, list[str]] = {}
    for selector, body in re.findall(r"([^{}]+)\{([^}]*)\}", css):
        theme = "light" if 'data-theme="light"' in selector else "dark"
        for name, value in re.findall(r"--([\w-]+):\s*([^;]+);", body):
            colour = _hex(value.strip())
            if colour:
                found.setdefault(colour, []).append(f"var(--{name}) ({theme})")
    return found


def lint(board: Path, values: dict[str, list[str]]) -> tuple[list[str], list[str]]:
    text = board.read_text()
    errors, warnings = [], []
    at = text.find(SUPPORT)
    if at < 0 or not KIT_LINK.match(text, at + len(SUPPORT)):
        errors.append("does not link kit/tokens.css right after its support.js line")
    allowed = [m.span() for m in ART.finditer(text)]
    for match in COLOUR.finditer(text):
        if any(start <= match.start() < end for start, end in allowed):
            continue
        line = text.count("\n", 0, match.start()) + 1
        literal = match.group(0)
        errors.append(f"{line}: colour literal {literal}")
        token = values.get(_hex(literal) or "")
        if token:
            more = f" (+{len(token) - 3} more)" if len(token) > 3 else ""
            warnings.append(f"{line}: {literal} = {', '.join(token[:3])}{more}")
    return errors, warnings


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("folder", type=Path, help="the folder holding the .dc.html boards")
    parser.add_argument("--kit", type=Path, required=True, help="the kit's tokens.css")
    parser.add_argument("--canvas", type=Path, required=True, help="the canvas's canvas.json")
    parser.add_argument("--all-pages", action="store_true", help="the archive too")
    args = parser.parse_args(argv)

    boards = json.loads(args.canvas.read_text())["boards"]
    values = kit_values(args.kit.read_text())
    failed = False
    for path in sorted(args.folder.glob("*.dc.html")):
        entry = boards.get(path.name)
        if entry is None:
            print(f"{path.name}: not on the canvas, skipped")
            continue
        if entry.get("page") == "archive" and not args.all_pages:
            continue
        errors, warnings = lint(path, values)
        for error in errors:
            print(f"{path.name}: error · {error}")
        for warning in warnings:
            print(f"{path.name}: warning · {warning}")
        if not errors and not warnings:
            print(f"{path.name}: clean")
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
