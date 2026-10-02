# HeaderActionRow

The action band on a media detail page: one wide control that fills the row, optional square discs beside it, and the consequence sentence underneath.

Rendered from `lib/core/widgets/header_action_row.dart` (`HeaderActionRow`, `ActionStateGlyph`, `HeaderActionButton`) and `lib/features/discover/presentation/widgets/discover_action_buttons.dart` (`DiscoverActionButtons`, the Seerr deck) by `test/design_catalog/header_action_row_catalog_test.dart`. The library bands compose the row the way `lib/core/widgets/library_detail_actions.dart` does, with the real ladder strings from `lib/core/status/media_action.dart`; the Seerr deck scenes render the widget itself, fed through `seerrRequestGate`.

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

## The Seerr deck

`DiscoverActionButtons` is the band on a Seerr title, `crossAxisAlignment: start` so the captions hang under tops that align. It is the Request primary and at most two captioned buttons:

- **Trailers** only when Seerr sent something to play. With nothing to play there is no button, never a disabled one.
- **Manage** when Seerr holds a row for the title; otherwise **Open** (*Open in Radarr*, *Open in Sonarr*), the cross-service jump. Never both. Open is dimmed but tappable when that service is not set up here, and absent when it answered that it does not hold the title, or for a series Seerr sent without a TVDB id.

The primary says what Seerr would do with a request (`seerrRequestGate`, read from Seerr's record alone, its codes decoded in the server's own numbering: Seerr's 6 is a blocklisted title, Overseerr's 6 and Seerr's 7 a deleted one, which can be requested again; the 4K copy is read from its own fields once Seerr is known to have a 4K server), with one `bodySmall` line under it when it does not act or acts for one copy only:

| State | Label | Line under it |
|---|---|---|
| Seerr would take a request | **Request** | none, or for a series partly on disk the seasons a request would add: *Seasons 3 and 4 are not requested yet.* |
| Seerr would take only a 4K request: the standard copy is on disk or asked for, and Seerr has a 4K server | **Request** | *Only the 4K copy can be requested.*, or for a series partly on disk in 4K *Seasons 3 and 4 are not requested in 4K yet.* The sheet offers the 4K servers only and opens on the default one. |
| Everything Seerr can hold is on disk | **Available** | *Already in your library, nothing to request.* |
| A request is waiting on somebody | **Requested** | *Waiting for approval in Seerr.* |
| Approved, or already in the arr | **Requested** | *Radarr is already tracking this.* |
| The last request failed | **Request failed** | *Seerr could not send the last request to Radarr.* |
| The operator blocklisted it in Seerr | **Blocklisted** | *Blocklisted in Seerr, which takes no request for it.* |

A state that does not act keeps its label legible: the secondary ink on the room's strong fill, not Material's 38% grey.

## Rungs

A primary takes one visible secondary (Interactive search first) plus `more_horiz`; a withheld primary frees both slots as labelled tonal buttons. Delete is never visible — sheet only.

## Semantics

Discs carry their name on the icon (`More actions`, `Interactive search`). A `HeaderActionButton` caption is excluded because the button already speaks its name (`semanticLabel` when the caption is shorter, e.g. *Trailers and teasers*). The confirmed glyph speaks *&lt;label&gt; complete*.

## The consumer provides

The controls, their callbacks, the busy and confirmed flags, and the consequence sentence.

## States in the catalog

Each sheet is drawn in the dark and the light room; the bands also on the desktop.

- The library band: primary with two discs, busy, confirmed, withheld (two tonal buttons), nothing to promote.
- The Seerr deck: nothing requested, a series partly on disk, available, on disk in HD with a 4K server, requested, failed, blocklisted.
- `HeaderActionButton`: idle, busy, confirmed, `onPressed: null`, a long caption.
- Text at 200%: the partly held series deck, the library band, and the deck with Open dimmed.

## Do / don't

- Do keep every control at 48 and the busy controls in place.
- Do wrap every label in the reading-size clamp.
- Don't make a visible Delete; don't round a control into a pill.
- Don't use `fixedSize` on a labelled control.
