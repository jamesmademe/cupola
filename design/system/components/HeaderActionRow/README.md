# HeaderActionRow

The action band on a media detail page: one wide control that fills the row, optional square discs beside it, and the consequence sentence underneath.

Hand-written from `lib/core/widgets/header_action_row.dart`, as `lib/core/widgets/library_detail_actions.dart` and `features/discover/presentation/widgets/discover_action_buttons.dart` use it. Labels and sentences are the real ladder strings from `core/status/media_action.dart`.

- Row: expanded child, `space-sm`, trailing; centred, or top-aligned when a trailing control hangs a caption.
- Every control is 48px tall (`buttonHeight`, the larger of 44pt / 48dp); targets are ≥ `space-sm` apart. Shape `radius-md` (12px), the interactive radius — full or near-full radius is the metadata shape.
- **Primary** (`expandedButtonStyle`): fill = the service accent, label and 18px glyph in `foregroundOn(accent)` (`ink-on-bright` on Radarr and Lidarr, white on Seerr and Sonarr), `label-large` 600, padding `space-md`, grows rather than clipping; label wraps to two lines, clamped at 1.6×.
- **Disc** (`tonalIconButtonStyle`): 48 × 48, `on-surface` at 6%, 1px `outline-variant`, 18px glyph in `on-surface-variant`. **Tonal** (`tonalExpandedButtonStyle`): the same fill as a labelled button, padding `space-sm`, no glyph.
- **Glyph states** (`ActionStateGlyph`): idle icon → busy 16px spinner (2px stroke) → confirmed `check`, the success green walked against the fill, held 1600ms. Cross-fade + 0.7 → 1 scale over 200ms; Reduce Motion swaps.
- **Captioned** (`HeaderActionButton`): a disc in a 72px column with a `label-small` 600 caption `space-xs` below, two lines, wrapping.
- **Gated** (`HeaderActionButton.annotate`, handed in by `CrossServiceAction.builder` or `CapabilityGatedAction.builder`): the glyph and caption drain to 38% together while the plate and 48px target stay; the button keeps its name and gains the hint (*Open in Radarr*, *requires Radarr*). A tap raises the toast whose action opens that service's settings.
- Consequence: `body-small`, `on-surface-variant`, up to three lines, `space-sm` under the row.

Rungs: a primary takes one visible secondary (Interactive search first) plus `more_horiz`; a withheld primary frees both slots as labelled tonal buttons. Delete is never visible — sheet only. While busy the secondaries stay in place, disabled, so nothing reflows under the thumb.

Discs carry their name on the icon (`More actions`, `Interactive search`); a caption is excluded because the button already speaks it; the confirmed state speaks *Automatic search complete*.

The consumer provides the controls, their callbacks and the consequence sentence.

- Do keep every control at 48px and the busy secondaries in place.
- Don't make a visible Delete; don't round a control into a pill.
