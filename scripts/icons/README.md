# Icon pipeline

Every icon Cupola ships descends from `masters.py`. The geometry lives there as
constants; nothing downstream carries any. Change the mark by editing that file,
never by touching an output.

## Changing the icon

```bash
scripts/generate_icons.sh --write             # regenerate every target in place
git diff --stat                               # review
scripts/generate_icons.sh --refresh-manifest  # re-record output hashes
scripts/verify_icons.sh                       # the gate CI also runs
```

The manifest refresh is deliberately separate: `--write` never touches
`scripts/icon_outputs.json`, so a change gets looked at before it is recorded.

**Requirements for `--write`:** `python3` with Pillow, and `node`/`npx` for the
SVG rasteriser (`@resvg/resvg-js-cli`, fetched on demand). This is a
developer-machine operation. CI only runs `--check`, which needs neither.

## The two files

`masters.py` holds the geometry and emits SVG masters into `.build/`, plus the
three canonical compositions in `assets/brand/`. `export.py` decides which master
goes to which target, at what size, with which alpha policy. If you are changing
how the mark *looks*, you want the first; how it is *delivered*, the second.

## Appearance mapping

| Target | Light | Dark | Themed |
|---|---|---|---|
| iOS / macOS | Icon Composer `Light` layer group | `Dark` layer group | tinted (grayscale master) |
| Android | `mipmap-*` + `drawable/` | `mipmap-night-*` + `drawable-night/` | `cupola_icon_monochrome` |
| Web | `favicon-light.png` | `favicon.png` | — |
| Windows / Linux | — | the dark appearance | — |

Windows, Linux and the legacy Apple `.appiconset` catalogues have no appearance
channel, so they carry the dark appearance: the product's committed identity.

### Android has a real fallback to think about

A launcher resolves the icon in its own configuration context, and not every
launcher honours `-night` there. When it does not, the unqualified resource wins,
so a dark-theme user on such a launcher sees the *light* icon. That is why the
light appearance has to stand on its own and not merely be a variant.

Background and foreground must always be changed together. Swapping only
`drawable/` leaves a dark structure sitting on a pale ground; `verify_icons.sh`
fails when the two grounds are identical, which is the signal that the split has
silently regressed.

### Apple's layers are not a picture

`icon.json` composes six layers (core, panes, frame, in light and dark), and the
system applies glass, specular and refraction on top. The ground is *not* a
layer: it comes from the `fill-specializations` gradient in `icon.json`, which
`export.py` keeps in step with the light body colour.

Consequence worth knowing: what those layers look like once the system has lit
them cannot be reproduced from the command line. `verify_icons.sh` runs `actool`,
which proves the bundle compiles, not that it looks right. Judge appearance in
Icon Composer or on a device.

## Small sizes

Below 64px the cloud passes only add mud, so every small target takes a
simplified twin: same geometry, no clouds, no spill. `SIMPLE_BELOW` in
`export.py` is the threshold; `icon-simple` and `icon-simple-light` are the
twins.

## Alpha

Transparency is kept only where something else composites the asset: Apple's
layer groups, Android's adaptive foreground and themed icon, and
`assets/brand/cupola_mark.png`, which `ServiceRing` draws over the app's own
surface. Everywhere else it is flattened: on Apple's 1024 marketing slot an
alpha channel is an App Store submission blocker.

## What is not generated

`assets/brand/cupola_mark.png` **is** generated (it is a real app asset declared
in `pubspec.yaml`). `.build/` is scratch and untracked. Nothing else under
`assets/` belongs to the icon system.
