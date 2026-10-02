# Design tokens

This folder is the single source of Cupola's design tokens: colour, spacing,
radius, component sizes, breakpoints, motion, type and elevation. The app never
states these values anywhere else. Its token classes (`AppColors`,
`CupolaRoom`, `AppSpacing`, `AppRadius`, `AppSize`, `AppElevation`,
`AppAnimation`, `AppBreakpoints`, `AppType`, the colour schemes and the type
ramp in `lib/core/theme.dart`) read them from a Dart file generated from this
folder.

## Layout

The tokens are written in the [W3C Design Tokens format](https://www.designtokens.org/tr/drafts/format/)
(`$value`, `$type`, `$description`, groups, and `{group.token}` aliases), split
into token sets:

| File | Set | Holds |
| --- | --- | --- |
| `core.json` | `core` | Everything shared by both themes: the fixed palette (service and section accents, the dark room's tone bytes, the plate, the neutral lamp), the spacing scale, radius, component sizes, breakpoints, motion (durations and curves), the type families and roles, and the shadow geometry. |
| `theme/dark.json` | `theme/dark` | The dark room: its steps (`color.room`), lines, fills, inks and five tones as drawn, the colour-scheme roles built on them, dim text, glass and glow opacities, and each shadow layer's opacity. |
| `theme/light.json` | `theme/light` | The same roles for the day room. |
| `$themes.json` | — | The two themes, each using `core` as its source set and enabling its own theme set. |
| `$metadata.json` | — | The order of the sets. |

Some groups carry two vocabularies over one scale: the component names the
layouts are drawn with (`space.scale`, `radius.slab`, `motion.standard`,
`type.role.screen`) and the older ladder the code has always read
(`space.lg`, `radius.md`, `duration.sm`, `type.headline.large`), whose steps
are aliases of the component value each one stands for. Change a value in the
component vocabulary; the ladder follows.

Beyond the format's simple types the generator reads two composites:

- `typography` — `{fontFamily, fontSize, lineHeight, fontWeight, fontWidth,
  letterSpacing}`. `fontFamily` may alias a `fontFamily` token; `lineHeight` is
  a length (divided by the size), a multiple or a percentage; `fontWeight` is
  any `wght` value from 1 to 1000; `fontWidth` is the `wdth` axis in percent;
  `letterSpacing` is a length or an `em` value (multiplied by the size). A
  whole role may alias another (`"{type.role.section}"`). Each typography
  token becomes one constant per property (`…FontFamily`, `…FontSize`,
  `…LineHeight` as a multiple, `…FontWeight`, `…Wght` for the exact axis value,
  `…FontWidth`, `…LetterSpacing` in pixels).
- `cubicBezier` — four numbers, or the CSS forms (`cubic-bezier(…)`, `ease`,
  `linear`, `ease-in`, `ease-out`, `ease-in-out`). It becomes a Flutter
  `Cubic`.

A set's name is its path in this folder without `.json`. Both theme sets must
define exactly the same roles; a token in `core` may alias only other `core`
tokens, and a theme token may alias `core` tokens or tokens of its own set.

## Editing

Edit the sets in whichever way suits you:

- **Any text editor.** The files are plain JSON.
- **A token editor that syncs with a Git repository.** Point it at this
  repository with `design/tokens` as the folder, stored as multiple files in
  the W3C format. It reads and writes the sets, `$themes.json` and
  `$metadata.json` in place.
- **A design tool that imports token folders.** Import this folder: each file
  becomes a set, and `$themes.json` the themes. Export back over it in the same
  layout when you are done.

Then regenerate:

```sh
dart run tool/design_tokens/generate.dart
```

This validates the sets (types, values, aliases, duplicates, and that both
themes define every role) and rewrites:

- `lib/core/generated/design_tokens.g.dart`, the Dart constants;
- `design/system/tokens.json`, the flat listing the design-system reference
  reads.

Commit the token sets together with both generated files.

## Rules

- **Never edit a generated file by hand.** The test suite regenerates both
  outputs from this folder and fails if either differs from what is committed,
  so an edit on one side only cannot land. `dart run
  tool/design_tokens/generate.dart --check` runs the same comparison on its
  own.
- **Values are tokens, behaviour is code.** The variable axes each face has,
  the contrast walk that keeps accent and tone labels legible, and the
  composition of shadows and borders stay in Dart; this folder carries the
  numbers they use.
- **Keep `$description` short.** One or two sentences on when to use the
  token. The reasoning behind a value lives in the doc comment of the Dart
  constant that exposes it.
- **An ink the room draws translucent is carried flattened in the scheme.**
  `color.ink.secondary` is white at 72%; `color.on-surface-variant` is the
  same ink flattened on the ground, because a contrast can only be measured
  between opaque colours. Change both together.
- Some editors write plural or property-specific type names back (for example
  `spacing`, `borderRadius`, `fontSizes`, `fontWeights`, `opacity`, `easing`).
  The generator reads them as the format type they mean, so a round trip does
  not break the build.
