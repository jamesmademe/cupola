# Button

The three Material buttons as Cupola's theme restyles them: filled for the one primary action on a surface, outlined for a secondary action, text for a recovery verb or a cross-service link.

Rendered from `lib/core/theme.dart` (`filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme`) and, for the gated state, `lib/core/widgets/cross_service_action.dart`, by `test/design_catalog/button_catalog_test.dart`.

## Variants

- **Filled** — `primary` fill, `on-primary` label in `label-large` 600, `radius-md`, padding `space-md` × `space-xl`. One per surface.
- **Outlined** — transparent, 1px `outline`, `primary` label, same radius and padding. Secondary actions beside a filled one.
- **Text** — `primary` label in `label-large` 600, no container. Recovery verbs (*Retry*, *Refresh*) and cross-service links (*Open in qBittorrent*).
- **Gated** — any of the three handed through `CrossServiceAction.builder` or `CapabilityGatedAction.builder`: the label and glyph drain to 38%, the container, border and target stay at full strength, and the button stays pressable. A tap raises the toast whose action is the fix.

## Size

The theme sets padding, not a height, so the painted height is the label's line plus its padding, and the tap target is whatever the platform's density adds around it.

| Platform | Filled | Outlined | Text | Tap target |
| --- | --- | --- | --- | --- |
| iOS, Android | 41 | 41 | 40 | padded to 48 (`MaterialTapTargetSize.padded`) |
| macOS, Windows, Linux | 32 | 32 | 32 | the painted box: desktop density is compact (−2, −2) and targets shrink-wrap |

## The consumer provides

The label (sentence case, a verb) and an optional leading icon (Material Icons Round, 18px). For a gated button, the `annotate` function the gate hands the builder, applied to the button's content.

## Semantics

Material's button node. A gated button keeps `enabled: true` and adds a hint (*requires qBittorrent*, *requires a read-write key*), annotated on the content inside the button.

## Do / don't

- Do keep a 44pt minimum target wherever a finger can reach; never add `VisualDensity.compact` — it silently cancels `minimumSize`.
- Do use a red fill only for an irreversible action (see AppDialog).
- Don't paint a recovery verb in `error`.
- Don't use a full-radius pill for a button: controls take the 12dp radius.
- Don't put a second filled button on the same surface.
- Don't pass `onPressed: null` to express "not available here" — gate it instead.
