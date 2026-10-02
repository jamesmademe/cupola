# Button

The three Material buttons as Cupola's theme restyles them: filled for the one primary action on a surface, outlined for a secondary action, text for a recovery verb or a cross-service link.

Rendered from `lib/core/theme.dart` (`filledButtonTheme`, `outlinedButtonTheme`, `textButtonTheme`, `floatingActionButtonTheme`), `lib/core/widgets/failure_remedy.dart` (`remedyFillStyle`) and, for the gated state, `lib/core/widgets/cross_service_action.dart`, by `test/design_catalog/button_catalog_test.dart`.

## Variants

- **Filled** — `primary` fill (the ink: `#F7F6F2` dark, `#16151A` light), `on-primary` label in the row role (15 / 600), `radius-control` (14), padding `space-md` × `space-lg`, 44 high at minimum. One per surface.
- **Outlined** — the ghost button: `fill-control` (white at 8% dark, ink at 8% light) with a 1px `line-edge` side, `on-surface` label, same radius, padding and label. Secondary actions beside a filled one.
- **Floating** — `FloatingActionButton` and `.extended` take the ink button's colours from the theme: `primary` fill, `on-primary` glyph and label, Material's own shape and size. A screen's one floating action is its primary, so it is never filled with a service's colour (the TrueNAS consoles used to fill theirs with TrueNAS blue).
- **Text** — `primary` label in `label-large` 600, no container. Recovery verbs (*Retry*, *Refresh*) and cross-service links (*Open in qBittorrent*).
- **Remedy** — the one fill a fault gets: an amber fault's remedy (*Paste the key again*, *Check the address*, or *Retry* where retrying is the fix) in `tone.amber-fill` under `tone.amber-ink` (`remedyFillStyle` in `lib/core/widgets/failure_remedy.dart`), the theme's radius and label, 44 high at standard density. `compact: true` is the fault line's control: 56 wide at minimum, padding `space-md`. Retry beside a red line is never this: it is the ghost (outlined) in a centred state and text in ink on a line. `test/core/widgets/failure_remedy_test.dart` measures the ink on the fill in both rooms.
- **Gated** — any of the three handed through `CrossServiceAction.builder` or `CapabilityGatedAction.builder`: the label and glyph drain to 38%, the container, border and target stay at full strength, and the button stays pressable. A tap raises the toast whose action is the fix.

## Focus

A button holding keyboard focus is ringed: a 2pt stroke in `line.focus` (the secondary ink), 2pt outside the shape and concentric with it (`FocusRingBorder` in `lib/core/focus_ring.dart`, resolved on `WidgetState.focused` by the filled, outlined, text and icon-button themes). Outside and apart, because on the edge of the ink button the secondary ink would vanish into the ink; the theme's focus overlay still shades the fill. A tap never focuses a button, so only a keyboard (a desktop, a tablet with one) ever draws it. A button whose own style sets `shape` takes no ring: give it the theme's.

## Size

The theme sets a 44 minimum height (`size.button-m`); the padding is `space-md` above and below the row role's 20pt line, which lands on the same 44. The three button themes and the icon-button theme pin `VisualDensity.standard`: the desktop's default compact density would take 8 off each, so buttons paint the same height on every platform and only the tap target differs. A bare `IconButton` is 40 on a desktop, padded to 48 on a phone.

| Platform | Filled | Outlined | Text | Tap target |
| --- | --- | --- | --- | --- |
| iOS, Android | 44 | 44 | 44 | padded to 48 (`MaterialTapTargetSize.padded`) |
| macOS, Windows, Linux | 44 | 44 | 44 | the painted box (targets shrink-wrap on a desktop) — 38 is the floor for a pointer-only control |

## The consumer provides

The label (sentence case, a verb) and an optional leading icon (Material Icons Round, 18px). For a gated button, the `annotate` function the gate hands the builder, applied to the button's content.

## Semantics

Material's button node. A gated button keeps `enabled: true` and adds a hint (*requires qBittorrent*, *requires a read-write key*), annotated on the content inside the button.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- Resting: filled with a leading icon, outlined and text.
- Floating: `FloatingActionButton` and `.extended`.
- Gated: the three buttons with label and glyph at 38%, container kept.
- Remedy: regular and compact, beside `Retry` in ink.
- `onPressed: null`: Material's disabled filled and outlined.
- A long label: each button grows to a second line instead of clipping.
- Text at 200%: every kind, the gated one and the remedy, at twice the reading size.
- Focused (desktop sheet): the filled button holding keyboard focus, ringed; focus is global to a render, so one control holds it per sheet.

## Do / don't

- Do keep a 44pt minimum target wherever a finger can reach; never add `VisualDensity.compact` — it silently cancels `minimumSize`.
- Don't use a red fill, not even for a delete: red means unreachable and nothing else. A destructive button is the theme's own, and its label says what it does (see AppDialog).
- Don't paint a recovery verb in `error`.
- Don't use a full-radius pill for a button: controls take the 14dp radius.
- Don't put a second filled button on the same surface.
- Don't give anything but a fault's remedy the amber fill, and never fill a Retry that sits beside silence.
- Don't pass `onPressed: null` to express "not available here" — gate it instead.
