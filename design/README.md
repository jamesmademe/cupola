# Design

Cupola's design system, kept as plain files beside the code so it can be read and changed with any
editor, reviewed like code, and never drift from the app.

| Path | What it holds | Edited by hand? |
|---|---|---|
| `tokens/` | The design tokens — colour, spacing, radius, type, motion, elevation — in the W3C Design Tokens format, as token sets Tokens Studio and Penpot read directly. **The single source of every value the app paints.** | Yes |
| `system/README.md` | The brand book: voice, colour, type, layout, shape, depth, motion, failure states, credential scope, accessibility, iconography. **The single statement of the design rules.** | Yes |
| `system/components/` | One card per widget: `<Card>/README.md` is its guide (variants, tokens, what the caller provides, semantics, do and don't); `README.md` indexes them by group. | Yes |
| `system/motion/` | Ten animated cards for the app's motion, the one place the system re-draws the app instead of rendering it. | Yes |
| `system/assets/` | How to use the brand and service marks, and the sample artwork the catalog draws with. | Yes |
| `system/tokens.json` | The tokens flattened for the motion cards and for any tool that wants one file. | No — generated |

The widgets themselves are the pictures. `test/design_catalog/` renders every card from the real
widget — one `*_catalog_test.dart` per card, the harness in `catalog.dart` — into
`build/design_catalog/<Card>/<phone|desktop>.<dark|light>.png`. The pictures are built, never
committed: they are deterministic on one machine, not across hosts, and a picture that can go stale
is exactly what the catalog replaces.

## Seeing it

```sh
python3 tool/design_system/gallery.py --render --serve
```

renders the catalog (`flutter test --tags catalog --run-skipped test/design_catalog`), builds
`build/design_system/index.html` — the brand book, then every card's guide beside its pictures, then
the motion cards playing in dark and light — and serves it on `http://127.0.0.1:8765/`. Drop
`--render` to rebuild the page from the pictures already there.

## Changing it

- **A value** — edit `tokens/core.json` or `tokens/theme/{dark,light}.json` (by hand, through Tokens
  Studio's GitHub sync pointed at `design/tokens/`, or by importing the sets into Penpot), then run
  `dart run tool/design_tokens/generate.dart` and commit the sets and the generated files together.
  The suite fails when they disagree (`test/tool/design_tokens_test.dart`).
- **A widget** — change it in `lib/`, re-render its card
  (`flutter test --tags catalog --run-skipped test/design_catalog/<card>_catalog_test.dart`), look at
  the pictures, and update the card's `README.md` in the same change. A new variant or state gets a
  scene; a new widget gets a card, a catalog test and a row in `system/components/README.md`.
- **A rule** — change `system/README.md`. Where a rule can be checked mechanically it is also a test
  (the weight ceiling, touch targets, accent contrast, the tone rule), and the test changes with it.
- **Motion** — change the constants in the Dart source and in the motion card together; both name
  them.

The app never hard-codes a token value: `lib/core/theme.dart`, `app_spacing.dart`, `app_radius.dart`,
`app_elevation.dart` and the rest read them from `lib/core/generated/design_tokens.g.dart`, and keep
only the behaviour — curves, the contrast walk, the tracking curve — that a token cannot express.
