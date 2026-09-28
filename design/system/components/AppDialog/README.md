# AppDialog

The one confirmation dialog in the app: title, a sentence, optional checkboxes, and a Cancel / confirm pair, with a destructive variant.

Rendered from `lib/core/widgets/app_dialog.dart` (`showAppConfirmDialog`, `AppConfirmOption`, `AppConfirmResult`) by `test/design_catalog/app_dialog_catalog_test.dart`, on Material 3 `AlertDialog`. The catalog opens the real dialog in each scene, barrier included.

## Anatomy

- **Surface**: `dialogTheme` — `surfaceContainer` in dark, `surface` in light — with `AppRadius.borderRadiusLg` (16) and no shadow. Material 3 metrics: 24 padding, 16 between title and content, 24 above the actions, actions right-aligned 8 apart. Barrier black at 54%; shown on the root navigator unless `useRootNavigator: false`.
- **Title row**: an optional 24pt icon, then `AppSpacing.md`, then the title in `titleLarge` at 600, two lines at most — an `AlertDialog` title sits above the scrollable content and could otherwise push the buttons off screen. Icon and title are `onSurface`, or the walked red when `destructive`.
- **Message**: `bodyMedium`.
- **Options**: `AppSpacing.md` above, one `CheckboxListTile` each — leading checkbox, zero content padding, the tile's own `bodyLarge` title and a `bodySmall` subtitle.
- **Danger note**: `AppSpacing.sm` above, padding `AppSpacing.md`, `AppRadius.borderRadiusSm`, the error fill at 10% with a 35% border, a 20pt `warning_rounded` glyph, `AppSpacing.sm`, then the text in `bodyMedium` at 600. Default copy *This cannot be undone.*; override it with `dangerNote`.
- **Actions**: a `TextButton` Cancel (`cancelLabel`, the theme's `primary` and `labelLarge` 600) and a `FilledButton` confirm (`confirmLabel`, default *Confirm*; the theme's `primary` fill, padding 24 × 12, `AppRadius.borderRadiusMd`).

## Colour

Red in a **status** means unreachable and nothing else; red in an **action** means irreversible. A delete confirmation is an action, so the destructive variant keeps its red — but every red ink is walked against the dialog's own surface:

- the title icon and title, and a checked danger option's title (`bodyLarge` 600) and subtitle: `statusToneColor(error, surface: dialog)`;
- the danger note's glyph and text: the same, against its 10% wash (`tintAlpha: 0.10`);
- the destructive confirm: fill `statusToneFill(error)`, label `ServiceTheme.foregroundOn(fill)` — the dark ink, on both themes.

## Variants

- **Standard** — the grab confirmation from the Interactive search sheet: *Grab release* (or *Grab rejected release*, with the rejections listed) / *Download "…"?* / Cancel, Download. An icon is optional (*Approve this request?*).
- **Destructive** (`destructive: true`) — the confirm fills red, and the title icon defaults to `warning_amber_rounded` and turns red. With no options the danger note always shows (*Delete snapshot?*, TrueNAS).
- **With options** — the note shows only while an option marked `danger` is checked, and that option's text turns red (*Remove from queue?* → *Delete from download client*, checked by default, and *Blocklist this release*). Unchecked, the dialog has no note and the confirm stays red.

## The consumer provides

Title, message, icon, labels, `dangerNote` and the options (`key`, `label`, `subtitle`, `initialValue`, `danger`). The result is `AppConfirmResult(confirmed, options)`, read with `option(key)`; dismissing returns `AppConfirmResult.cancelled`.

## Semantics

Material's: a dialog route, checkbox tiles that announce their state, two buttons.

## Do / don't

- Do phrase the title as the question and put the object in the message.
- Do override `dangerNote` when the default would overstate or understate the stakes.
- Don't add a third button.
- Don't use the destructive fill for anything that can be undone.
