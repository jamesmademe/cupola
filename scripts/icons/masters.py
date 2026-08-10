#!/usr/bin/env python3
"""Cupola icon geometry — the single source of the mark.

Every platform asset in the repository descends from the constants in this file.
Nothing downstream carries geometry: change a number here, run
`scripts/generate_icons.sh --write`, and all 80-odd outputs follow.

The mark is the ISS Cupola read the way its photographs read it, not the way its
floor plan does. Two rules carry that, and both are load-bearing:

  * The hexagon never appears as an outline. The body bleeds to the tile edge and
    the six-sidedness survives only as the ARRANGEMENT of six openings on a
    circle. Draw the hexagon as a closed figure and the icon becomes a hex nut,
    whatever else is done to it.
  * The openings look at something. One globe sits behind all seven of them, so
    the horizon cuts the two top openings and the light falls from the lower
    left. Six identical lit shapes at 60 degrees rebuild the hexagon in the
    viewer's eye no matter how the outline is treated; the asymmetry of a real
    view is what breaks it.

Outputs are written as SVG masters; `export.py` rasterises them per platform.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

# ------------------------------------------------------------------ geometry

C = 512

# Wider than deep, with a real margin around the assembly. Past a ~1.8:1 ring
# taper each opening turns into a shield and the mark into a flower; the
# reference plan views sit near 1.7:1.
RI = 248  # inner edge distance from centre
RO = 440  # outer edge distance from centre
WI = 112  # inner half-width
WO = 194  # outer half-width
K = 32  # corner radius

OCULUS_COLLAR = 196
OCULUS_GLASS = 152

# Android adaptive geometry.
#
# The foreground canvas is 108dp, but the launcher does not show it: it shows the
# central 72dp and scales THAT up to fill the icon slot. So sizing the mark to
# the 66dp safe circle — the obvious reading of the spec — lands it at 92% of the
# visible radius and it arrives edge-to-edge with no margin at all. The safe
# circle is a "must not exceed", not a "should fill".
#
# Aim instead at the proportion the mark has on iOS, where the system applies its
# own inset: roughly 70% of the visible tile.
ADAPTIVE_VISIBLE_DP = 72
ADAPTIVE_MARK_FRACTION = 0.70
ADAPTIVE_SCALE = round(
    ((ADAPTIVE_MARK_FRACTION * ADAPTIVE_VISIBLE_DP / 2) / 108 * 1024) / RO, 4
)

# Web maskable icons answer to a different rule: the safe area is a circle of 80%
# of the image, and the icon is expected to fill much more of the frame than an
# Android foreground does. It keeps the older, larger scale.
MASKABLE_SCALE = round(((33 / 108) * 1024) / RO, 4)

# Two openings top, two bottom, one each side — a rib sits at twelve o'clock,
# exactly as the module reads in the reference plan views.
ANGLES = (30, 90, 150, 210, 270, 330)


def n(value: float) -> str:
    """Trim a coordinate the way the geometry deserves: two decimals, no noise."""
    rounded = round(float(value), 2)
    if rounded == int(rounded):
        return str(int(rounded))
    return repr(rounded)


def rounded_poly(points, radius):
    count = len(points)

    def unit(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy)
        return dx / d, dy / d

    segments = []
    for i, p in enumerate(points):
        prev = points[(i - 1) % count]
        nxt = points[(i + 1) % count]
        din = unit(prev, p)
        dout = unit(p, nxt)
        segments.append(
            {
                "p": p,
                "start": (p[0] - radius * din[0], p[1] - radius * din[1]),
                "end": (p[0] + radius * dout[0], p[1] + radius * dout[1]),
            }
        )

    d = f"M {n(segments[0]['end'][0])} {n(segments[0]['end'][1])}"
    for i in range(1, count + 1):
        s = segments[i % count]
        d += f" L {n(s['start'][0])} {n(s['start'][1])}"
        d += f" Q {n(s['p'][0])} {n(s['p'][1])} {n(s['end'][0])} {n(s['end'][1])}"
    return d + " Z"


PANE = rounded_poly(
    [
        (C - WI, C - RI),
        (C + WI, C - RI),
        (C + WO, C - RO),
        (C - WO, C - RO),
    ],
    K,
)


def scale_at(factor: float) -> str:
    if factor == 1:
        return ""
    return f"translate({C} {C}) scale({factor}) translate({-C} {-C}) "


def panes(pre: str = "") -> str:
    return "\n      ".join(
        f'<path d="{PANE}" transform="{pre}rotate({a} {C} {C})"/>' for a in ANGLES
    )


def oculus_at(pre: str = "") -> str:
    transform = f' transform="{pre.strip()}"' if pre else ""
    return f'<circle cx="{C}" cy="{C}" r="{OCULUS_GLASS}"{transform}/>'


# -------------------------------------------------------------------- shells


def svg(label: str, body: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
        f'width="1024" height="1024" role="img" aria-label="{label}">\n{body}\n</svg>\n'
    )


def all_clip(p: str, pre: str = "") -> str:
    return f"""<clipPath id="{p}-all">
      {panes(pre)}
      {oculus_at(pre)}
    </clipPath>"""


def blur(ident: str, deviation: float) -> str:
    return (
        f'<filter id="{ident}" x="-45%" y="-45%" width="190%" height="190%" '
        f'color-interpolation-filters="sRGB"><feGaussianBlur stdDeviation="{deviation}"/></filter>'
    )


def wells(
    p: str,
    shapes: str,
    *,
    shade: str,
    light: str,
    shade_opacity: float,
    light_opacity: float,
    width: int = 34,
    light_width: int = 12,
    dx: int = 9,
    dy: int = 12,
) -> str:
    """Well walls, painted INSIDE the opening clip.

    The shaded wall is broad; the lit wall is a narrow crescent hugging the far
    rim. Widening that second stroke is what turns every opening into a plastic
    pillow, so it stays thin. The oculus gets its own tighter pass: a broad soft
    gradient inside a circle is the exact recipe for a sphere, and a sphere is a
    marble, not a window.
    """
    return f"""
    <g filter="url(#{p}-soft)" opacity="{shade_opacity}">
      <g fill="none" stroke="{shade}" stroke-width="{width}" transform="translate({-dx} {-dy})">
      {shapes}
      </g>
    </g>
    <g filter="url(#{p}-tight)" opacity="{light_opacity}">
      <g fill="none" stroke="{light}" stroke-width="{light_width}" transform="translate({dx} {dy})">
      {shapes}
      </g>
    </g>"""


def collar(palette: dict, pre: str = "") -> str:
    """A machined band between the glass and the body, hairlined on both edges.

    It is the whole reason the centre reads as an oculus rather than a hub.
    """
    mid = (OCULUS_GLASS + OCULUS_COLLAR) / 2
    width = OCULUS_COLLAR - OCULUS_GLASS
    transform = f' transform="{pre.strip()}"' if pre else ""
    return f"""<g{transform}>
    <circle cx="{C}" cy="{C}" r="{n(mid)}" fill="none" stroke="{palette['band']}" stroke-width="{width}"/>
    <circle cx="{C}" cy="{C}" r="{OCULUS_COLLAR - 3}" fill="none" stroke="{palette['outer']}" stroke-width="5" stroke-opacity="0.75"/>
    <circle cx="{C}" cy="{C}" r="{OCULUS_GLASS + 3}" fill="none" stroke="{palette['inner']}" stroke-width="5" stroke-opacity="0.7"/>
  </g>"""


# ------------------------------------------------------------ the view (Earth)

# One globe, close enough that its limb curves visibly inside a 1024 frame. Sit
# it further away and the horizon flattens into a straight line that reads as a
# paint edge rather than a planet.
EARTH = {"cx": 430, "cy": 1030, "r": 820}

SKY = {
    "space": ("#050A1E", "#0D1636"),
    "deep": "#1B34A6",
    "mid": "#3C7BEC",
    "rim": ("#8FC3FA", "#E2F0FF"),
    "halo": "#A9CCFF",
    "night": "#03050F",
}

SKY_GREY = {
    "space": ("#454545", "#525252"),
    "deep": "#8C8C8C",
    "mid": "#BCBCBC",
    "rim": ("#E2E2E2", "#F6F6F6"),
    "halo": "#EDEDED",
    "night": "#3C3C3C",
}


def scene_defs(p: str, sky: dict) -> str:
    cx, cy, r = EARTH["cx"], EARTH["cy"], EARTH["r"]
    return f"""
    <linearGradient id="{p}-space" x1="0.82" y1="0" x2="0.2" y2="0.55">
      <stop offset="0" stop-color="{sky['space'][0]}"/>
      <stop offset="1" stop-color="{sky['space'][1]}"/>
    </linearGradient>
    <radialGradient id="{p}-earth" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">
      <stop offset="0.08" stop-color="{sky['deep']}"/>
      <stop offset="0.7" stop-color="{sky['mid']}"/>
      <stop offset="0.93" stop-color="{sky['rim'][0]}"/>
      <stop offset="0.988" stop-color="{sky['rim'][1]}"/>
      <stop offset="1" stop-color="#F2F7FF"/>
    </radialGradient>
    <radialGradient id="{p}-halo" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r + 64}">
      <stop offset="0.94" stop-color="{sky['halo']}" stop-opacity="0"/>
      <stop offset="0.965" stop-color="{sky['halo']}" stop-opacity="0.5"/>
      <stop offset="0.988" stop-color="{sky['halo']}" stop-opacity="0.72"/>
      <stop offset="1" stop-color="{sky['halo']}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="{p}-airglow" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r + 96}">
      <stop offset="0.955" stop-color="{sky['halo']}" stop-opacity="0"/>
      <stop offset="0.985" stop-color="{sky['halo']}" stop-opacity="0.22"/>
      <stop offset="1" stop-color="{sky['halo']}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="{p}-terminator" x1="0.06" y1="1" x2="0.94" y2="0.06">
      <stop offset="0" stop-color="{sky['night']}" stop-opacity="0"/>
      <stop offset="0.55" stop-color="{sky['night']}" stop-opacity="0.14"/>
      <stop offset="1" stop-color="{sky['night']}" stop-opacity="0.34"/>
    </linearGradient>"""


def scene(p: str, cloud_opacity: float = 0.5, simple: bool = False) -> str:
    cx, cy, r = EARTH["cx"], EARTH["cy"], EARTH["r"]
    # Below roughly 64px the cloud passes only add mud, so the simplified twin
    # drops them and keeps the same geometry.
    clouds = (
        ""
        if simple
        else f"""<g fill="#FDFDFF" opacity="{cloud_opacity}" filter="url(#{p}-cloud)">
        <ellipse cx="250" cy="520" rx="210" ry="96" transform="rotate(-22 250 520)"/>
        <ellipse cx="470" cy="556" rx="150" ry="74" transform="rotate(-14 470 556)"/>
        <ellipse cx="556" cy="742" rx="242" ry="104" transform="rotate(-16 556 742)"/>
        <ellipse cx="868" cy="640" rx="146" ry="80" transform="rotate(-24 868 640)"/>
        <ellipse cx="308" cy="920" rx="200" ry="86" transform="rotate(-12 308 920)"/>
      </g>
      <g fill="#FFFFFF" opacity="{round(cloud_opacity * 0.72, 4):g}" filter="url(#{p}-wisp)">
        <ellipse cx="286" cy="486" rx="118" ry="34" transform="rotate(-26 286 486)"/>
        <ellipse cx="512" cy="612" rx="96" ry="26" transform="rotate(-16 512 612)"/>
        <ellipse cx="628" cy="716" rx="140" ry="32" transform="rotate(-18 628 716)"/>
        <ellipse cx="452" cy="836" rx="126" ry="30" transform="rotate(-12 452 836)"/>
        <ellipse cx="838" cy="602" rx="88" ry="24" transform="rotate(-28 838 602)"/>
        <ellipse cx="196" cy="880" rx="132" ry="30" transform="rotate(-10 196 880)"/>
      </g>"""
    )
    return f"""
      <rect width="1024" height="1024" fill="url(#{p}-space)"/>
      <circle cx="{cx}" cy="{cy}" r="{r + 96}" fill="url(#{p}-airglow)"/>
      <circle cx="{cx}" cy="{cy}" r="{r + 64}" fill="url(#{p}-halo)"/>
      <circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#{p}-earth)"/>
      {clouds}
      <rect width="1024" height="1024" fill="url(#{p}-terminator)"/>"""


# -------------------------------------------------------------------- palettes

DARK = {
    "body": ("#2A344E", "#141A29", "#05060B"),
    "body_centre": ("42%", "30%"),
    "hairline": "#7E8AB4",
    "hairline_opacity": 0.48,
    "collar": {"band": "#0A0D18", "inner": "#CBD2FF", "outer": "#4C5878"},
    "well_shade": "#04050A",
    "well_light": "#F2F4FF",
    "spill": "#7C86F6",
    "spill_opacity": 0.3,
    "vignette": ("#000000", 0.58),
}

LIGHT = {
    "body": ("#FBFCFE", "#DFE4EF", "#98A1B7"),
    "body_centre": ("32%", "22%"),
    "hairline": "#7C8499",
    "hairline_opacity": 0.5,
    "collar": {"band": "#DDE1EC", "inner": "#FFFFFF", "outer": "#8B93A8"},
    "well_shade": "#02030A",
    "well_light": "#C9D4FF",
    "spill": "#8892F5",
    "spill_opacity": 0.16,
    "vignette": ("#5A6480", 0.42),
}

PALETTES = {"dark": DARK, "light": LIGHT}

# The Android adaptive background is an XML gradient rather than a bitmap, so the
# body palette has to exist in a form Android can read. Angle 270 runs top to
# bottom, matching the top-lit radial body closely enough at icon scale.
ANDROID_GROUND = {
    "light": ("#FBFCFE", "#DFE4EF", "#98A1B7"),
    "dark": ("#2A344E", "#141A29", "#05060B"),
}


def ground(p: str, pal: dict) -> str:
    return f"""
    <radialGradient id="{p}-body" cx="{pal['body_centre'][0]}" cy="{pal['body_centre'][1]}" r="92%">
      <stop offset="0" stop-color="{pal['body'][0]}"/>
      <stop offset="0.46" stop-color="{pal['body'][1]}"/>
      <stop offset="1" stop-color="{pal['body'][2]}"/>
    </radialGradient>
    <radialGradient id="{p}-vignette" cx="48%" cy="42%" r="76%">
      <stop offset="0.58" stop-color="{pal['vignette'][0]}" stop-opacity="0"/>
      <stop offset="1" stop-color="{pal['vignette'][0]}" stop-opacity="{pal['vignette'][1]}"/>
    </radialGradient>"""


RELIEF = {
    "light": {"ao": 0.46, "hi": ("#FFFFFF", 7, 0.62), "lo": ("#6E778E", 8, 0.45)},
    "dark": {"ao": 0, "hi": ("#AEB8DA", 6, 0.34), "lo": ("#02030A", 7, 0.6)},
}


def relief(p: str, pre: str, appearance: str) -> str:
    """Machined rim, laid down BEFORE the openings are painted.

    The opening then crops each stroke: the offset-up-left highlight survives
    only along the lit edge, the offset-down-right shade only along the far one.
    On the light appearance an occlusion pass also seats the openings into the
    body; on the dark one that pass would be invisible, so it is skipped rather
    than shipped as decoration.
    """
    cfg = RELIEF[appearance]
    shapes = f"{panes(pre)}\n      {oculus_at(pre)}"
    ao = (
        f"""  <g mask="url(#{p}-outside)">
    <g filter="url(#{p}-ao)" opacity="{cfg['ao']}" fill="none" stroke="#4E5670" stroke-width="24">
      {shapes}
    </g>
  </g>"""
        if cfg["ao"]
        else ""
    )
    return f"""{ao}
  <g fill="none" stroke="{cfg['hi'][0]}" stroke-width="{cfg['hi'][1]}" stroke-opacity="{cfg['hi'][2]}" transform="translate(-5 -6)">
    {shapes}
  </g>
  <g fill="none" stroke="{cfg['lo'][0]}" stroke-width="{cfg['lo'][1]}" stroke-opacity="{cfg['lo'][2]}" transform="translate(5 6)">
    {shapes}
  </g>"""


# --------------------------------------------------------------------- builder


def icon(
    *,
    ident: str,
    label: str,
    appearance: str = "dark",
    scale: float = 1,
    with_ground: bool = True,
    simple: bool = False,
) -> str:
    p = ident
    pal = PALETTES[appearance]
    pre = scale_at(scale)

    raw = scene(p, 0.5, simple)
    fill = f'<g transform="{pre.strip()}">{raw}</g>' if pre else raw

    outside_mask = (
        f"""<mask id="{p}-outside">
      <rect width="1024" height="1024" fill="#FFFFFF"/>
      <g fill="#000000">
        {panes(pre)}
        {oculus_at(pre)}
      </g>
    </mask>"""
        if appearance == "light"
        else ""
    )

    spill = (
        ""
        if simple
        else f"""  <g filter="url(#{p}-glow)" opacity="{pal['spill_opacity']}" fill="{pal['spill']}">
    {panes(pre)}
    {oculus_at(pre)}
  </g>"""
    )

    body = f"""  <defs>
{ground(p, pal) if with_ground else ''}
{scene_defs(p, SKY)}
    {blur(f'{p}-soft', 11)}
    {blur(f'{p}-tight', 7)}
    {blur(f'{p}-glow', 34)}
    {blur(f'{p}-ao', 15) if appearance == 'light' else ''}
    {blur(f'{p}-cloud', 30)}
    {blur(f'{p}-wisp', 12)}
    {all_clip(p, pre)}
    {outside_mask}
  </defs>
{f'''
  <rect width="1024" height="1024" fill="url(#{p}-body)"/>''' if with_ground else ''}
{f'  <rect width="1024" height="1024" fill="url(#{p}-vignette)"/>' if appearance == 'light' and with_ground else ''}

{spill}
{relief(p, pre, appearance)}

  <g clip-path="url(#{p}-all)">
      {fill}
{wells(p, panes(pre),
       shade=pal['well_shade'], light=pal['well_light'],
       shade_opacity=0.74 if appearance == 'light' else 0.62,
       light_opacity=0.1 if appearance == 'light' else 0.13)}
{wells(p, oculus_at(pre),
       shade=pal['well_shade'], light=pal['well_light'],
       shade_opacity=0.5 if appearance == 'light' else 0.42,
       light_opacity=0.08, width=16, light_width=9, dx=5, dy=7)}
  </g>

  <g fill="none" stroke="{pal['hairline']}" stroke-width="4" stroke-opacity="{pal['hairline_opacity']}">
    {panes(pre)}
  </g>

  {collar(pal['collar'], pre)}
{f'  <rect width="1024" height="1024" fill="url(#{p}-vignette)"/>' if appearance == 'dark' and with_ground else ''}"""

    return svg(label, body)


def mono(label: str, scale: float = 1) -> str:
    """Android themed icon and macOS menu bar: pure silhouette on transparent.

    The oculus becomes a ring rather than a filled disc — a solid dot in the
    middle of six shapes reads as a hub, and the whole argument is that the
    centre is a window.
    """
    pre = scale_at(scale)
    ring_mid = (OCULUS_GLASS + OCULUS_COLLAR) / 2
    transform = f' transform="{pre.strip()}"' if pre else ""
    return svg(
        label,
        f"""  <g fill="#FFFFFF">
    {panes(pre)}
  </g>
  <circle cx="{C}" cy="{C}" r="{n(ring_mid)}" fill="none" stroke="#FFFFFF" stroke-width="{OCULUS_COLLAR - OCULUS_GLASS - 8}"{transform}/>""",
    )


def tinted(ident: str, label: str) -> str:
    """iOS tinted appearance: grayscale, transparent ground.

    Luminance carries the design here, so the asymmetry survives — the two
    openings onto space stay darker than the five onto the planet, which flat
    monochrome cannot express.
    """
    p = ident
    ring_mid = (OCULUS_GLASS + OCULUS_COLLAR) / 2
    return svg(
        label,
        f"""  <defs>
{scene_defs(p, SKY_GREY)}
    {blur(f'{p}-cloud', 30)}
    {blur(f'{p}-wisp', 12)}
    {blur(f'{p}-soft', 11)}
    {blur(f'{p}-tight', 7)}
    {all_clip(p)}
  </defs>

  <g clip-path="url(#{p}-all)">
      {scene(p)}
{wells(p, panes(), shade='#2E2E2E', light='#FFFFFF', shade_opacity=0.5, light_opacity=0.14)}
  </g>
  <circle cx="{C}" cy="{C}" r="{n(ring_mid)}" fill="none" stroke="#666666" stroke-width="{OCULUS_COLLAR - OCULUS_GLASS}"/>""",
    )


def layer(ident: str, label: str, appearance: str, part: str) -> str:
    """One Icon Composer layer.

    Apple lights, refracts and tints these independently, so the ground is
    deliberately not among them: it comes from icon.json's fill gradient. Each
    layer carries only what sits on top of it, on a transparent canvas.
    """
    p = ident
    pal = PALETTES[appearance]

    if part == "frame":
        cfg = RELIEF[appearance]
        shapes = f"{panes()}\n      {oculus_at()}"
        ao = (
            f"""    <g filter="url(#{p}-ao)" opacity="{cfg['ao']}" fill="none" stroke="#4E5670" stroke-width="24">
      {shapes}
    </g>"""
            if cfg["ao"]
            else ""
        )
        return svg(
            label,
            f"""  <defs>
    {blur(f'{p}-ao', 15)}
    <mask id="{p}-outside">
      <rect width="1024" height="1024" fill="#FFFFFF"/>
      <g fill="#000000">
        {panes()}
        {oculus_at()}
      </g>
    </mask>
  </defs>

  <g mask="url(#{p}-outside)">
{ao}
    <g fill="none" stroke="{cfg['hi'][0]}" stroke-width="{cfg['hi'][1]}" stroke-opacity="{cfg['hi'][2]}" transform="translate(-5 -6)">
      {shapes}
    </g>
    <g fill="none" stroke="{cfg['lo'][0]}" stroke-width="{cfg['lo'][1]}" stroke-opacity="{cfg['lo'][2]}" transform="translate(5 6)">
      {shapes}
    </g>
  </g>
  <g fill="none" stroke="{pal['hairline']}" stroke-width="4" stroke-opacity="{pal['hairline_opacity']}">
    {panes()}
  </g>""",
        )

    is_core = part == "core"
    shapes = oculus_at() if is_core else panes()
    return svg(
        label,
        f"""  <defs>
{scene_defs(p, SKY)}
    {blur(f'{p}-soft', 11)}
    {blur(f'{p}-tight', 7)}
    {blur(f'{p}-cloud', 30)}
    {blur(f'{p}-wisp', 12)}
    <clipPath id="{p}-clip">
      {shapes}
    </clipPath>
  </defs>

  <g clip-path="url(#{p}-clip)">
      {scene(p)}
{wells(p, shapes,
       shade=pal['well_shade'], light=pal['well_light'],
       shade_opacity=(0.5 if appearance == 'light' else 0.42) if is_core
                     else (0.74 if appearance == 'light' else 0.62),
       light_opacity=0.08 if is_core else (0.1 if appearance == 'light' else 0.13),
       width=16 if is_core else 34,
       light_width=9 if is_core else 12,
       dx=5 if is_core else 9,
       dy=7 if is_core else 12)}
  </g>
{f"  {collar(pal['collar'])}" if is_core else ''}""",
    )


def preview_ground(label: str) -> str:
    """The pale ground Icon Composer shows behind the light group while editing."""
    return svg(
        label,
        f"""  <defs>{ground('pg', LIGHT)}</defs>
  <rect width="1024" height="1024" fill="url(#pg-body)"/>""",
    )


def android_ground_xml(appearance: str) -> str:
    start, centre, end = ANDROID_GROUND[appearance]
    which = "dark theme" if appearance == "dark" else "the default/light appearance"
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!--
  Adaptive-icon background for {which}. Generated by
  scripts/icons/masters.py from the body palette; edit the palette there, never
  this file. The light and night grounds intentionally differ — the matching
  foreground carries the same appearance, so the two must be changed together.
-->
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:angle="270"
        android:startColor="{start}"
        android:centerColor="{centre}"
        android:endColor="{end}"
        android:type="linear" />
</shape>
"""


# ------------------------------------------------------------------------ emit


def build() -> dict[str, str]:
    files: dict[str, str] = {
        # Full compositions.
        "icon-dark.svg": icon(ident="id", label="Cupola icon, dark appearance"),
        "icon-light.svg": icon(
            ident="il", label="Cupola icon, light appearance", appearance="light"
        ),
        "icon-simple.svg": icon(
            ident="is", label="Cupola icon, simplified for small sizes", simple=True
        ),
        "icon-simple-light.svg": icon(
            ident="isl",
            label="Cupola icon, light appearance simplified for small sizes",
            appearance="light",
            simple=True,
        ),
        # The mark with no ground: the geometry source of record.
        "mark.svg": icon(ident="mk", label="Cupola mark", with_ground=False),
        # Web maskable: the assembly pulled inside the safe zone, ground included.
        "maskable.svg": icon(
            ident="mb", label="Cupola icon, maskable", scale=MASKABLE_SCALE
        ),
        # System variants.
        "mono.svg": mono("Cupola icon, monochrome", ADAPTIVE_SCALE),
        "tinted.svg": tinted("tn", "Cupola icon, iOS tinted appearance"),
        # Android adaptive foregrounds, one per appearance.
        "android-fg-dark.svg": icon(
            ident="afd",
            label="Cupola adaptive foreground, dark appearance",
            scale=ADAPTIVE_SCALE,
            with_ground=False,
        ),
        "android-fg-light.svg": icon(
            ident="afl",
            label="Cupola adaptive foreground, light appearance",
            appearance="light",
            scale=ADAPTIVE_SCALE,
            with_ground=False,
        ),
        "preview-ground.svg": preview_ground("Cupola icon preview ground"),
    }

    for appearance in ("light", "dark"):
        for part in ("core", "panes", "frame"):
            files[f"layer-{part}-{appearance}.svg"] = layer(
                f"l{part[0]}{appearance[0]}",
                f"Cupola icon layer, {part}, {appearance} appearance",
                appearance,
                part,
            )

    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="directory for the SVG masters")
    parser.add_argument(
        "--brand", help="assets/brand directory; when given, the canonical SVGs are refreshed"
    )
    args = parser.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    files = build()
    for name, content in files.items():
        (out / name).write_text(content, encoding="utf-8")

    if args.brand:
        brand = Path(args.brand)
        brand.mkdir(parents=True, exist_ok=True)
        # The three roles the repository's icon policy defines.
        (brand / "cupola_mark.svg").write_text(files["mark.svg"], encoding="utf-8")
        (brand / "cupola_icon.svg").write_text(files["icon-dark.svg"], encoding="utf-8")
        (brand / "cupola_launcher.svg").write_text(files["icon-simple.svg"], encoding="utf-8")

    print(f"masters: {len(files)} SVG in {out}  (adaptive {ADAPTIVE_SCALE}, maskable {MASKABLE_SCALE})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
