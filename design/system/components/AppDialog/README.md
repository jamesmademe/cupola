# AppDialog

The one confirmation dialog in the app, in one style: title, a sentence, optional checkboxes, and a Cancel / confirm pair whose confirm names what will happen. A delete looks like every other confirmation. A typed variant gates the few actions that reach past the device.

Rendered from `lib/core/widgets/app_dialog.dart` (`showAppConfirmDialog`, `showAppTypedConfirmDialog`, `AppConfirmOption`, `AppConfirmResult`) by `test/design_catalog/app_dialog_catalog_test.dart`, on Material 3 `AlertDialog`. The catalog opens the real dialog in each scene, barrier included.

## Anatomy

- **Surface**: `dialogTheme` — `surfaceContainer` in dark, `surface` in light — with `AppRadius.borderRadiusLg` (16) and no shadow. Material 3 metrics: 24 padding, 16 between title and content, 24 above the actions, actions right-aligned 8 apart. Barrier black at 54%; shown on the root navigator unless `useRootNavigator: false`.
- **Title row**: an optional 24pt icon in `onSurface`, then `AppSpacing.md`, then the title in `titleLarge` at 600, two lines at most — an `AlertDialog` title sits above the scrollable content and could otherwise push the buttons off screen.
- **Message**: `bodyMedium`.
- **Options**: `AppSpacing.md` above, one `CheckboxListTile` each — leading checkbox, zero content padding, the tile's own `bodyLarge` title and a `bodySmall` subtitle.
- **Actions**: a `TextButton` Cancel (`cancelLabel`, the theme's `primary` and `labelLarge` 600) and the theme's own `FilledButton` confirm (`confirmLabel`; `primary` fill, padding 24 × 12, `AppRadius.borderRadiusMd`). No style of its own. A label too long to sit beside Cancel makes the pair stack rather than truncate, with the confirm on top and Cancel beneath it, 8 apart (`actionsOverflowDirection: VerticalDirection.up`, Material's stacked order).
- **Typed variant** (`showAppTypedConfirmDialog`): the same title row and message, then `AppSpacing.md`, the phrase on a `surfaceContainerHighest` plate (`AppRadius.borderRadiusSm`, padding 12 × 8, `bodyMedium` 600, selectable), `AppSpacing.md`, a text field labelled *Type it to confirm*, autofocused. The confirm stays disabled until the field matches the phrase, trimmed and case-insensitive.

## Colour

None of its own. **A destructive confirmation is not red**: red in the tone rule means unreachable and nothing else, and a delete, a stop or a reset is an action, not a status. The icon is `onSurface`, every line of text is the dialog's own ink, the confirm is the theme's `primary`. `test/core/widgets/app_dialog_test.dart` walks every text, glyph and fill in the dialog on both themes and fails on any red; `test/core/theme/neutral_destructive_test.dart` fails on any button style or dialog in `lib/` built with the error colour.

It used to have a `destructive` variant — red fill, red title and glyph, a red *This cannot be undone.* banner — on the theory that red on an action meant irreversible. That exception is gone, and so are `destructive`, `dangerNote` and `AppConfirmOption.danger`.

## The weight is carried by words

- **The confirm label is a verb and its object** — *Delete job*, *Take down*, *Remove from Radarr*, *Stop playback* — never *Confirm*, *OK*, *Yes*, or a bare *Delete*. `confirmLabel` is required; the scan above rejects a single word.
- **When an option changes what the action does, the label says so** (`confirmLabelFor`): *Remove from queue* becomes *Remove and delete files* when *Delete from download client* is ticked. `confirmLabel` must be the label for the options' initial values; the helper asserts it.
- **If it cannot be undone, one neutral sentence says so**, in the message (*This cannot be undone.*), or in the subtitle of the option that makes it so. An action that can be undone says nothing of the sort — *Forget certificate*, *Stop playback*.

## Variants

- **Standard** — the grab confirmation from the Interactive search sheet: *Grab release* (or *Grab rejected release*, with the rejections listed) / *Download "…"?* / Cancel, *Download release*. An icon is optional (*Approve this request?* → *Approve request*).
- **A delete with options** — *Remove from queue?* with *Delete from download client* (ticked by default, its subtitle ending *This cannot be undone.*) and *Blocklist this release*; the confirm reads *Remove and delete files*, and *Remove from queue* once the first is unticked.
- **A delete with no options** — *Delete snapshot?* / *tank/media@… is destroyed. This cannot be undone.* / *Delete snapshot* (TrueNAS).
- **Typed** — *Shut down nas?*, the hostname to type, *Shut down server* inert until it matches (TrueNAS power; NPM's *Take offline* and *Save and reload* go through the same helper).

## The consumer provides

Title, message, icon, `confirmLabel`, optionally `confirmLabelFor`, `cancelLabel` and the options (`key`, `label`, `subtitle`, `initialValue`). The result is `AppConfirmResult(confirmed, options)`, read with `option(key)`; dismissing returns `AppConfirmResult.cancelled`. The typed variant takes `phrase` and returns whether it was confirmed. A haptic, where a flow wants one, is the caller's, fired before the dialog opens.

## Semantics

Material's: a dialog route, checkbox tiles that announce their state, two buttons. The typed variant's disabled confirm carries the hint *Type <phrase> above to enable*, on the button's label — a `Semantics(hint:)` wrapped around a button is dropped.

## Do / don't

- Do phrase the title as the question and put the object in the message.
- Do make the confirm label say the whole of what happens, options included.
- Don't paint any part of a confirmation red, amber or with any other tone. The words carry it.
- Don't write *This cannot be undone.* for something that can be.
- Don't add a third button.
