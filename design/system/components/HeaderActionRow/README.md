# HeaderActionRow

The action band on a media detail page: one wide control that fills the row, optional square discs beside it, and the consequence sentence underneath.

Rendered from `lib/core/widgets/header_action_row.dart` (`HeaderActionRow`, `ActionStateGlyph`) by `test/design_catalog/header_action_row_catalog_test.dart`. The catalog composes the library band from these pieces, with the ladder's strings from `lib/core/status/media_action.dart`. A movie's or a series' page has its own lead and buttons: see [MediaPage](../MediaPage/README.md).

## The row

- `HeaderActionRow(expanded:, trailing:, crossAxisAlignment:)`: `expanded` fills the row, `AppSpacing.sm` (8), then `trailing`. Centred by default; `CrossAxisAlignment.start` when a trailing control hangs a caption, so the tops align and the caption hangs below.
- `HeaderActionRow.buttonHeight` is **52**, `size.button-l`: the brand book's primary, which the promoted verb is, above the 48 touch floor (the larger of iOS 44pt and Android 48dp); the discs take it too, so a band has one height. Every control's shape is `radius.button` (16), continuous, and ringed in `line.focus` while the keyboard holds it (the styles take the `BuildContext` for it: a style that sets its own shape replaces the theme's ring). Adjacent targets are at least `AppSpacing.sm` apart.
- Every control uses `AppRadius.borderRadiusMd` (14), the control radius. None is drawn as a pill.

## Styles

- **Primary** (`expandedButtonStyle`): a `FilledButton.icon`, the ink button: `primary` fill with the label and 18pt glyph in `on-primary`, on every service — the promoted verb is never the service's colour. The theme's button text (the row role, 15 / 600), horizontal padding `AppSpacing.md`, `minimumSize` 52 high and never `fixedSize`, so a label that no longer fits grows the button instead of breaking mid-word. The expanded styles pin `VisualDensity.standard`, so on a desktop they stay 52 beside the 52pt discs instead of losing 8 to compact density. The label wraps to two lines under the 1.6× reading-size clamp (`TextScaleMetrics.clampedScalerOf`).
- **Disc** (`tonalIconButtonStyle`): an `OutlinedButton` fixed at 52 × 52, `onSurface` at 6%, a 1px `outlineVariant` side, 18pt glyph in `onSurfaceVariant`. `iconOnlyButtonStyle` is the filled equivalent, an ink square.
- **Tonal** (`tonalExpandedButtonStyle`): the disc's fill and side on a labelled button 48 high with `AppSpacing.md` padding; the band narrows that to `AppSpacing.sm` and drops the glyph so two labels fit a phone row.
- **Consequence**: `bodySmall` in `onSurfaceVariant`, up to three lines, `AppSpacing.sm` under the row. When nothing is promoted and nothing is surfaced, the sentence takes the `expanded` slot itself.

## ActionStateGlyph

Idle icon (18pt) → busy spinner (16pt, 2pt stroke, this control's work only) → confirmed `check_rounded`, the theme's success green (`tertiary`) walked through `ServiceTheme.onTint` against the fill it sits on. The host holds the check for `AppAnimation.confirmationHold` (1600 ms). Faces cross-fade with a 0.7 → 1 scale over `AppAnimation.durationSm` (320 ms); with Reduce Motion they swap. While a band is busy the host passes `onPressed: null`, so the primary and its discs take Material's disabled colours and stay in place — nothing reflows under the thumb.

## Rungs

A primary takes one visible secondary (Interactive search first) plus `more_horiz`; a withheld primary frees both slots as labelled tonal buttons. Delete is never visible — sheet only.

## Semantics

Discs carry their name on the icon (`More actions`, `Interactive search`). The confirmed glyph speaks *&lt;label&gt; complete*.

## The consumer provides

The controls, their callbacks, the busy and confirmed flags, and the consequence sentence.

## States in the catalog

Each sheet is drawn in the dark and the light room; the bands also on the desktop.

- The library band: primary with two discs, busy, confirmed, withheld (two tonal buttons), nothing to promote.
- Text at 200%: the library band.

## Do / don't

- Do keep every control at 48 and the busy controls in place.
- Do wrap every label in the reading-size clamp.
- Don't make a visible Delete; don't round a control into a pill.
- Don't use `fixedSize` on a labelled control.
