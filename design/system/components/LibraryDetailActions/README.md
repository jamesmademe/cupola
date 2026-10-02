# LibraryDetailActions

The deck of a Radarr, Sonarr or Lidarr detail page: one status in, one promoted verb out, a sentence saying what follows, and everything else behind an overflow.

Rendered from `lib/core/widgets/library_detail_actions.dart` and `header_action_row.dart`, with the promotion ladder in `lib/core/status/media_action.dart` and the sheets and dialogs around it (`media_detail_value_row.dart` → `showMediaValueSheet` / `MediaValueOptionRow`, `media_search_popup_menu.dart`, `delete_media_dialog.dart` → `showAppConfirmDialog` in `app_dialog.dart`), by `test/design_catalog/library_detail_actions_catalog_test.dart`.

- **Band** — a `HeaderActionRow` (the wide control, `AppSpacing.sm` (8), the trailing controls), then 8 and the consequence in `bodySmall` `onSurfaceVariant`, three lines at most. Every control declares a 48pt height (`HeaderActionRow.buttonHeight`), `AppRadius.md`, 8 apart. Never padded by the caller: the detail spine owns the gutter.
- **Promoted verb** — `FilledButton.icon`, the remaining width, the ink button — `primary` fill with its label and glyph in `on-primary`, the same on every service, never the service's colour — padding `AppSpacing.md` (12) horizontal, an 18pt glyph (`ActionStateGlyph`), the theme's button text (15 / 600), wrapping to two centred lines (text clamped at 1.6×) rather than breaking a word. Busy (`isBusy`): the glyph becomes a 16pt, 2pt-stroke spinner and **nothing in the band takes a tap** — the promoted button, the discs and the overflow all disable. The promoted button keeps its ink fill and on-ink while disabled, because it is the one carrying the spinner; the discs take the disabled look. Landed (`isConfirmed`): a check in the theme's success green, walked by `onTint` against the ink fill, holds for `AppAnimation.confirmationHold`. Label and glyph cross-fade on change unless Reduce Motion is on.
- **Secondaries** — tonal: `onSurface` at 6%, 1px `outlineVariant`, `onSurfaceVariant` ink. With a primary: one 48 × 48 icon disc (Interactive search ranks first, then Automatic search, Manual import, Monitor). Without a primary: the two best-ranked as labelled buttons sharing the width, padding 8, no glyph (the words are the affordance), two lines at most. Delete is never visible.
- **Overflow** — a 48 × 48 disc with `more_horiz_rounded`, shown whenever something did not earn a visible slot. It opens the *Actions* sheet (`AppBottomSheet`, subtitle the media title, the service's accent — the lamp) with whatever is left, in this order: Interactive search, Automatic search, Monitor / Stop monitoring, Manual import, then a divider (`outlineVariant`, 24 high) and Delete last, in the same ink as every other row — set apart by place, never by red. Rows are at least 48 high: 18pt glyph, 12, `bodyLarge` w600. The sheet spends itself on one tap and fires one haptic (medium for Delete, selection click otherwise).
- **Ladder** (`resolveMediaAction`, real strings, `<Service>` is the service's title):
  - Missing → *Automatic search*, "<Service> is hunting a release for this title." Partial → *Automatic search*, or the caller's `partialSummary`.
  - Upgradable → *Interactive search*, "The file is below your quality cutoff, so <Service> keeps looking."
  - Unmonitored and not available → *Monitor*, "<Service> isn't searching for this title."
  - Import blocked → *Finish import*, "The download is done; <Service> needs a hand importing it."
  - Failed and stalled → *Interactive search*, with what the service reported quoted ("<Service> reports: …").
  - Queued, downloading, import pending, importing, paused, client unavailable → *Open queue*, with a sentence for each (downloading carries the percentage).
  - Available → no primary, "<Service> has everything it expects, so it isn't searching." Not released → no primary, "There's nothing to search for until it's released." (`consequenceOverride` names the date). Deleted and unknown have their own sentences and no primary.
  - A rung whose callback is missing promotes nothing and keeps only its sentence.
- **Quality profile sheet** — not part of this band: it opens from the profile's value row in the Details card (`showMediaProfileSelector` → `showMediaValueSheet`). One field per sheet: title *Quality profile*, subtitle *Currently HD-1080p*, `tune_rounded` in the header, option rows at least 48 high with an 18pt glyph, 12, `bodyLarge`. Selected: `check_circle_rounded` and a w600 label in the primary ink (the page's accent is the lamp, which `onTint` resolves to ink); others `circle_outlined` in `onSurfaceVariant`, label w500.
- **Search menu** (`MediaSearchPopupMenu`, season and album rows) — a `search` icon button, 20pt by default, tooltip *Search options*, opening a Material 3 menu: *Automatic search*, *Interactive search*. While searching it is replaced by a 20pt, 2pt-stroke spinner.
- **Delete dialog** (`showDeleteMediaDialog`) — the shared `showAppConfirmDialog` (see AppDialog), neutral like every confirmation: *Delete Nosferatu?* in `titleLarge` w600 (two lines at most), no icon; "This will remove this movie from Radarr." in `bodyMedium`; 12; two leading-checkbox rows (*Add list exclusion* / "Prevent this movie from being re-added by lists"; *Delete files* / "Deletes the downloaded files from disk. This cannot be undone."). Actions: *Cancel* (text button) and the theme's `FilledButton`, which reads *Delete movie* (*series*, *artist*) and *Delete movie and files* once *Delete files* is ticked. No red anywhere. The dialog opens on the root navigator, so the catalog does not draw it.

The consumer provides `service`, the resolved `status`, `mediaTitle`, `isMonitored`, `isBusy` / `isConfirmed`, optionally `partialSummary` and `consequenceOverride`, and the callbacks (`onSearch`, `onInteractiveSearch`, `onImport`, `onOpenQueue`, `onMonitoredChanged`, `onDelete`). A missing callback withholds that action entirely rather than disabling it. Titles and profile names in the catalog are illustrative.

Semantics: disc glyphs carry the accessible name (*Interactive search*, *More actions*); the busy spinner keeps the action's label and the confirmed glyph announces *<label> complete*. Sheet rows speak their label once; a selected profile row adds the value *Selected*.

Do: map every in-flight flag onto `isBusy`; set a destructive row apart by where it sits — below the divider, last — and by its `mediumImpact` haptic. Don't: add a quality-profile control to the band — a detail edits in place, on its value row; don't paint anything red but unreachability — a destructive row takes the same `onSurface` label and `onSurfaceVariant` glyph as every other row.

## States in the catalog

Each sheet is drawn in the dark and the light room; the band also on the desktop.

- Each rung of the ladder: missing, upgradable, missing and unmonitored, import blocked, downloading, failed, available, busy, confirmed.
- Sonarr partial, Lidarr not released, only Delete wired, nothing wired.
- The quality profile sheet body, `MediaSearchPopupMenu` idle, searching and open.
- Text at 200%: missing, failed, available and downloading.
