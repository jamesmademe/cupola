"""The design tokens as CSS: custom properties per theme, and the text roles.

Read from design/system/tokens.json, which tool/design_tokens/generate.dart
writes from design/tokens/. Shared by the brand book (gallery.py), whose
motion frames paint over the same ground the app does, and by the canvas kit
(canvas_kit.py), whose boards may use nothing else.
"""

from __future__ import annotations

import re
from typing import Callable


def _css_value(value: str) -> str:
    alias = re.fullmatch(r"\{(.+)\}", value)
    return f"var(--{alias.group(1)})" if alias else value


def _per_theme(value, theme: str, first: str) -> str:
    if isinstance(value, str):
        return value
    return value.get(theme, value[first])


def tokens_css(tokens: dict, font_url: Callable[[dict], str | None]) -> str:
    """Every token as a custom property: the colours and shadows once per
    theme (the first on `:root` too), the rest on `:root`, and an
    `@font-face` for each font [font_url] gives an address for."""
    themes = [t["id"] for t in tokens["color"]["themes"]]
    first = themes[0]
    blocks = []
    for index, theme in enumerate(themes):
        selector = f':root, [data-theme="{theme}"]' if index == 0 else f'[data-theme="{theme}"]'
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
    for family in ("spacing", "radius", "size", "breakpoint"):
        shared += [f"--{t['name']}: {t['value']};" for t in tokens.get(family, {}).get("tokens", [])]
    for key, stack in tokens["type"]["families"].items():
        shared.append(f"--font-{key}: {stack};")
    blocks.append(f":root {{ {' '.join(shared)} }}")
    for font in tokens["type"]["fonts"]:
        url = font_url(font)
        if url is None:
            continue
        stretch = f" font-stretch: {font['stretch']};" if font.get("stretch") else ""
        blocks.append(
            "@font-face { "
            f"font-family: \"{font['family']}\"; src: url(\"{url}\"); "
            f"font-weight: {font['weight']}; font-style: {font.get('style', 'normal')};{stretch} }}"
        )
    return "\n".join(blocks)


def type_css(tokens: dict) -> str:
    """A class per text role, `.t-<name>`: its family, size, line height,
    weight, width and tracking, as the app sets them."""
    rules = []
    for group in tokens["type"]["groups"]:
        for style in group["styles"]:
            props = [f"font-family: var(--font-{style['family']});"]
            if "fontSize" in style:
                props.append(f"font-size: {style['fontSize']};")
            if "lineHeight" in style:
                props.append(f"line-height: {style['lineHeight']};")
            if "fontWeight" in style:
                props.append(f"font-weight: {style['fontWeight']};")
            if "fontWidth" in style:
                props.append(f"font-stretch: {style['fontWidth']};")
            if "letterSpacing" in style:
                props.append(f"letter-spacing: {style['letterSpacing']};")
            rules.append(f".t-{style['name']} {{ {' '.join(props)} }}")
    return "\n".join(rules)
