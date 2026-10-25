# MediaDetailActions

What an artist's or an author's page keeps behind its overflow, and the small controls around it: the Actions sheet, the quality profile sheet, the search menu and the delete dialog.

Rendered from `lib/core/widgets/media_detail_actions.dart` (`showMediaDetailActions`, `MediaOverflowAction`) and the sheets and dialogs around it (`media_value_sheet.dart` → `showMediaValueSheet` / `MediaValueOptionRow` / `qualityProfileOptions`, `media_search_popup_menu.dart`, `delete_media_dialog.dart` → `showAppConfirmDialog` in `app_dialog.dart`), by `test/design_catalog/media_detail_actions_catalog_test.dart`.

- **Actions sheet** (`showMediaDetailActions`): an `AppBottomSheet` titled *Actions*, subtitle the media title, the service's accent (the lamp), listing what the page hands it in the order given, then a divider (`outlineVariant`, 24 high) and every destructive action last, in the same ink as every other row, set apart by place, never by red. A page cannot seat Delete beside Import: the sheet moves it. Rows are at least 48 high: 18pt glyph, 12, `bodyLarge` w600. The sheet spends itself on one tap, so a second finger on another row does nothing, and fires one haptic (medium for a destructive row, selection click otherwise). A row with no `onInvoke` is dimmed and takes no tap. **Where there is room** (`AppBreakpoints.sheetsAreDialogs`) and the page hands the button that asked (`anchor:`, the shelf page's ⋯ plate), the same actions are the theme's menu under that button instead (`room.menu`, `radius.lg`, its edge), lined up with whichever of its edges is nearer the window's, in the same order with a `PopupMenuDivider` before the destructive ones, one haptic as in the sheet; a row with no `onInvoke` is drawn off. A list of actions is the pointer's popover, never a dialog.
- **Quality profile sheet**: opens from the Quality profile row of an artist's or an author's page (`showMediaValueSheet` over `qualityProfileOptions`). One field per sheet: title *Quality profile*, subtitle *Currently HD-1080p*, `tune_rounded` in the header, option rows at least 48 high with an 18pt glyph, 12, `bodyLarge`. Selected: `check_circle_rounded` and a w600 label in the primary ink (the page's accent is the lamp, which `onTint` resolves to ink); others `circle_outlined` in `onSurfaceVariant`, label w500. `qualityProfileOptions` drops a profile that lacks its `id` or its `name` rather than drawing a blank row. Past twelve options (`mediaValueSearchFrom`) the sheet opens on the screens' search field (`MediaValueSearchList`, its hint the caller's: *Episode number or title* for a manual import's episode, *Track number or title* for a track), which narrows the rows as the user types, ignoring case (`mediaValueMatches`); a number is a whole number, so `17` finds `E17` and never `E117`. With nothing left, one dimmed line: *Nothing matches "zebra"*.
- **Search menu** (`MediaSearchPopupMenu`, season and album rows): a `search` icon button, 20pt by default, tooltip *Search options*, opening a Material 3 menu: *Automatic search*, *Interactive search*. While searching it is replaced by a 20pt, 2pt-stroke spinner.
- **Delete dialog** (`showDeleteMediaDialog`): the shared `showAppConfirmDialog` (see AppDialog), neutral like every confirmation: *Delete Nosferatu?* in `titleLarge` w600 (two lines at most), no icon; "This will remove this movie from Radarr." in `bodyMedium`; 12; two leading-checkbox rows (*Add list exclusion* / "Prevent this movie from being re-added by lists"; *Delete files* / "Deletes the downloaded files from disk. This cannot be undone."). Actions: *Cancel* (text button) and the theme's `FilledButton`, which reads *Delete movie* (*series*, *artist*) and *Delete movie and files* once *Delete files* is ticked. No red anywhere. The dialog opens on the root navigator, so the catalog does not draw it.
- **Ladder** (`resolveMediaAction`, real strings, `<Service>` is the service's title):
  - Missing → *Automatic search*, "<Service> is hunting a release for this title." Partial → *Automatic search*, or the caller's `partialSummary`.
  - Upgradable → *Interactive search*, "The file is below your quality cutoff, so <Service> keeps looking."
  - Unmonitored and not available → *Monitor*, "<Service> isn't searching for this title."
  - Import blocked → *Finish import*, "The download is done; <Service> needs a hand importing it."
  - Failed and stalled → *Interactive search*, with what the service reported quoted ("<Service> reports: …").
  - Queued, downloading, import pending, importing, paused, client unavailable → *Open queue*, with a sentence for each (downloading carries the percentage).
  - Available → no primary, "<Service> has everything it expects, so it isn't searching." Not released → no primary, "There's nothing to search for until it's released." (`consequenceOverride` names the date). Deleted and unknown have their own sentences and no primary.
  - A rung whose callback is missing promotes nothing and keeps only its sentence.

The consumer provides `accent`, the media `title` and the `MediaOverflowAction`s (`label`, `icon`, `onInvoke`; `MediaOverflowAction.destructive` for Delete). Titles and profile names in the catalog are illustrative.

Semantics: sheet rows speak their label once; a selected profile row adds the value *Selected*.

Do: set a destructive row apart by where it sits (below the divider, last) and by its `mediumImpact` haptic. Don't: add a quality-profile control to the Actions sheet. A detail edits in place, on its own row; don't paint anything red but unreachability: a destructive row takes the same `onSurface` label and `onSurfaceVariant` glyph as every other row.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The quality profile sheet body, `MediaSearchPopupMenu` idle, searching and open.
- The episode picker past twelve options, open and with `17` typed.
- Text at 200%: the quality profile sheet body.
