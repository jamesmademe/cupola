# HeaderActionRow

The action band on a media detail page: one wide control that fills the row, optional square discs beside it, and the consequence sentence underneath.

Rendered from `lib/core/widgets/header_action_row.dart` (`HeaderActionRow`, `ActionStateGlyph`, `HeaderActionButton`) by `test/design_catalog/header_action_row_catalog_test.dart`. The scenes compose the row the way `lib/core/widgets/library_detail_actions.dart` and `lib/features/discover/presentation/widgets/discover_action_buttons.dart` do, with the real ladder strings from `lib/core/status/media_action.dart`.

## The row

- `HeaderActionRow(expanded:, trailing:, crossAxisAlignment:)`: `expanded` fills the row, `AppSpacing.sm` (8), then `trailing`. Centred by default; `CrossAxisAlignment.start` when a trailing control hangs a caption, so the tops align and the caption hangs below.
- `HeaderActionRow.buttonHeight` is **48** — the larger of iOS 44pt and Android 48dp, and the primary's height, so a band has one height. Adjacent targets are at least `AppSpacing.sm` apart.
- Every control uses `AppRadius.borderRadiusMd` (14), the control radius. None is drawn as a pill.

## Styles

- **Primary** (`expandedButtonStyle`): a `FilledButton.icon`, the ink button: `primary` fill with the label and 18pt glyph in `on-primary`, on every service — the promoted verb is never the service's colour. The theme's button text (the row role, 15 / 600), horizontal padding `AppSpacing.md`, `minimumSize` 48 high and never `fixedSize`, so a label that no longer fits grows the button instead of breaking mid-word. The expanded styles pin `VisualDensity.standard`, so on a desktop they stay 48 beside the 48pt discs instead of losing 8 to compact density. The label wraps to two lines under the 1.6× reading-size clamp (`TextScaleMetrics.clampedScalerOf`).
- **Disc** (`tonalIconButtonStyle`): an `OutlinedButton` fixed at 48 × 48, `onSurface` at 6%, a 1px `outlineVariant` side, 18pt glyph in `onSurfaceVariant`. `iconOnlyButtonStyle` is the filled equivalent, an ink square.
- **Tonal** (`tonalExpandedButtonStyle`): the disc's fill and side on a labelled button 48 high with `AppSpacing.md` padding; the band narrows that to `AppSpacing.sm` and drops the glyph so two labels fit a phone row.
- **Consequence**: `bodySmall` in `onSurfaceVariant`, up to three lines, `AppSpacing.sm` under the row. When nothing is promoted and nothing is surfaced, the sentence takes the `expanded` slot itself.

## ActionStateGlyph

Idle icon (18pt) → busy spinner (16pt, 2pt stroke, this control's work only) → confirmed `check_rounded`, the theme's success green (`tertiary`) walked through `ServiceTheme.onTint` against the fill it sits on. The host holds the check for `AppAnimation.confirmationHold` (1600 ms). Faces cross-fade with a 0.7 → 1 scale over `AppAnimation.durationSm` (320 ms); with Reduce Motion they swap. While a band is busy the host passes `onPressed: null`, so the primary and its discs take Material's disabled colours and stay in place — nothing reflows under the thumb.

## HeaderActionButton

A disc in a 72pt column (`captionMeasure`, the 48 square plus `AppSpacing.xl`), with a `labelSmall` caption at 600 `AppSpacing.xs` below it: two lines, wrapping, centred, under the 1.6× clamp. The measure does not grow with the reading size — three of these beside a primary are a fixed budget on a 360pt phone — so a long caption takes its second line instead. `isBusy` and `isConfirmed` drive the glyph; `onPressed: null` dims the glyph only.

**Gated** (`annotate`, handed in by `CrossServiceAction.builder` or `CapabilityGatedAction.builder`): glyph and caption drain to 38% together while the plate and the 48pt target stay; the button keeps its name and gains the hint (*Open in Radarr*, *requires Radarr*). A tap raises the toast whose action opens that service's settings.

## Rungs

A primary takes one visible secondary (Interactive search first) plus `more_horiz`; a withheld primary frees both slots as labelled tonal buttons. Delete is never visible — sheet only.

## Semantics

Discs carry their name on the icon (`More actions`, `Interactive search`). A `HeaderActionButton` caption is excluded because the button already speaks its name (`semanticLabel` when the caption is shorter, e.g. *Trailers and teasers*). The confirmed glyph speaks *&lt;label&gt; complete*.

## The consumer provides

The controls, their callbacks, the busy and confirmed flags, and the consequence sentence.

## Do / don't

- Do keep every control at 48 and the busy controls in place.
- Do wrap every label in the reading-size clamp.
- Don't make a visible Delete; don't round a control into a pill.
- Don't use `fixedSize` on a labelled control.
