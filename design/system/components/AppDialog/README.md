# AppDialog

The one confirmation dialog in the app: title, a sentence, optional checkboxes, and a Cancel / confirm pair, with a destructive variant.

Hand-written from `lib/core/widgets/app_dialog.dart` (`showAppConfirmDialog`, `AppConfirmOption`, `AppConfirmResult`), on Material 3 `AlertDialog`.

## Anatomy

- **Surface**: `surface-container` in dark, `surface` in light (`dialogTheme`), `radius-lg`, no shadow. Material 3 metrics: 24 padding, 16 between title and content, 24 above the actions, actions right-aligned 8 apart. Barrier black at 54%, root navigator by default.
- **Title row**: optional 24px icon, then `space-md`, title `title-large` 600 in `on-surface`, two lines max (an `AlertDialog` title sits above the scroll and could push the buttons off screen).
- **Message** `body-medium`. **Options**: `space-md` above, one `CheckboxListTile` each (leading checkbox, zero content padding, title `body-large`, subtitle `body-small`).
- **Danger note**: `space-sm` above, padding `space-md`, `radius-sm`, `error` at 10% fill with a 35% border, `warning` glyph 20px, text `body-medium` 600. Default copy *This cannot be undone.*
- **Actions**: `TextButton` Cancel (`primary`, `label-large` 600) and `FilledButton` confirm (`primary`, padding 24 × 12, `radius-md`).

## Colour

Red in a **status** means unreachable and nothing else; red in an **action** means irreversible. A delete confirmation is an action, so the destructive variant keeps its red — but every red ink is walked against the dialog's own surface:

- icon and checked danger option: `statusToneColor(error, surface: dialog)`;
- danger note glyph and text: the same, against its 10% wash (`tintAlpha: 0.10`);
- destructive confirm: fill `statusToneFill(error)`, label `ServiceTheme.foregroundOn(fill)`.

## Variants

- **Standard** — the grab confirmation from the Interactive search sheet: *Grab release* (or *Grab rejected release*) / *Download "…"?* / Cancel, Download.
- **Destructive** (`destructive: true`) — the confirm fills red, the title icon defaults to `warning_amber` and turns red. With no options the danger note always shows (*Delete snapshot?*, TrueNAS).
- **With options** — a checked option marked `danger` turns its title (`body-large` 600) and subtitle red and raises the danger note (*Remove from queue?* → *Delete from download client* / *Blocklist this release*).

## The consumer provides

Title, message, icon, labels, `dangerNote` and the options. The result is `AppConfirmResult(confirmed, options)`; dismissing returns `cancelled`.

## Semantics

Material's: a dialog route, checkbox tiles that announce their state, two buttons.

## Do / don't

- Do phrase the title as the question and put the object in the message.
- Do override `dangerNote` when the default would overstate or understate the stakes.
- Don't add a third button.
- Don't use the destructive fill for anything that can be undone.
