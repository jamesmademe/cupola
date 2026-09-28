# Design

Cupola's design system, kept as plain files so it can be read and edited with any
editor or design tool, reviewed like code, and never drift from the app.

| Folder | What it holds | Edited by hand? |
|---|---|---|
| `tokens/` | The design tokens — colour, spacing, radius, type, motion, elevation — in the W3C Design Tokens format, as token sets that Tokens Studio and Penpot read directly. **The single source of every value the app paints.** | Yes |
| `system/` | The design system: `README.md` (the brand book — voice, colour, type, layout, shape, depth, motion, failure states, accessibility, iconography), one card per component under `components/<Card>/` (`preview.html`, a static rendition of the Flutter widget, and `README.md`, its guidelines), the shared card stylesheet and contrast helpers, and the notes on the brand assets. | Yes, except `tokens.json` |
| `system/tokens.json` | The tokens flattened for the cards and for any tool that wants one file. | No — generated |

## Changing a value

1. Edit `tokens/core.json` or `tokens/theme/{dark,light}.json` — in an editor, through Tokens
   Studio's GitHub sync pointed at `design/tokens/`, or by importing the sets into Penpot.
2. Regenerate the Dart constants and `system/tokens.json`:

   ```sh
   dart run tool/design_tokens/generate.dart
   ```

3. Commit the token sets and the generated files together. The test suite fails when they
   disagree (`test/tool/design_tokens_test.dart`).

The app never hard-codes a token value: `lib/core/theme.dart`, `app_spacing.dart`,
`app_radius.dart`, `app_elevation.dart` and the rest read them from
`lib/core/generated/design_tokens.g.dart`, and keep only the behaviour — curves, the contrast walk,
the tracking curve — that a token cannot express.

## Looking at the cards

```sh
python3 tool/design_system/gallery.py --serve
```

builds `build/design_system/index.html` — every card in dark and light at the width it is drawn
for — and serves it on `http://127.0.0.1:8765/`. Artwork in the cards (`__POSTER__`,
`__BACKDROP__`) comes from `system/assets/Imagery/`. The brand marks and service glyphs are not
copied here: they are `assets/brand/` and `tool/service_glyphs/svg/`.

## What the cards are, and are not

A card recreates a widget in HTML and CSS so the design can be read outside the Flutter code.
The widget is the truth: when a card and `lib/` disagree, the code is right and the card is
out of date.
