# Design tokens

This folder is the single source of Cupola's design tokens: colour, spacing,
radius, breakpoints, motion, type and elevation. The app never states these
values anywhere else. Its token classes (`AppColors`, `AppSpacing`,
`AppRadius`, `AppElevation`, `AppAnimation`, `AppBreakpoints`, the colour
schemes and the type ramp in `lib/core/theme.dart`) read them from a Dart file
generated from this folder.

## Layout

The tokens are written in the [W3C Design Tokens format](https://www.designtokens.org/tr/drafts/format/)
(`$value`, `$type`, `$description`, groups, and `{group.token}` aliases), split
into token sets:

| File | Set | Holds |
| --- | --- | --- |
| `core.json` | `core` | Everything shared by both themes: the fixed palette (service and section accents, status fills, brand indigo, plates), spacing, radius, breakpoints, durations, the type scale and the shadow geometry. |
| `theme/dark.json` | `theme/dark` | The dark theme's semantic roles: the colour-scheme roles, dim text, glass and glow opacities, and each shadow layer's opacity. |
| `theme/light.json` | `theme/light` | The same roles for the light theme. |
| `$themes.json` | — | The two themes, each using `core` as its source set and enabling its own theme set. |
| `$metadata.json` | — | The order of the sets. |

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
- **Values are tokens, behaviour is code.** Curves, Inter's tracking curve, the
  contrast walk that keeps accent labels legible, and the composition of
  shadows and borders stay in Dart; this folder carries the numbers they use.
- **Keep `$description` short.** One or two sentences on when to use the
  token. The reasoning behind a value lives in the doc comment of the Dart
  constant that exposes it.
- Some editors write plural or property-specific type names back (for example
  `spacing`, `borderRadius`, `fontSizes`, `fontWeights`, `opacity`). The
  generator reads them as the format type they mean, so a round trip does not
  break the build.
