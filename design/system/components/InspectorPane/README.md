# InspectorPane

The desktop window's right-hand column: the live queue, who did not answer, and what finished today, without leaving the page you are on.

Rendered from `lib/features/shell/presentation/desktop/inspector_pane.dart` (`InspectorPane`, `InspectorSplitHandle`) and `lib/features/shell/domain/inspector_state.dart` by `test/design_catalog/inspector_pane_catalog_test.dart`. Titles and figures are sample data.

- Width `InspectorState.defaultWidth` 360, clamped to 300–520, dragged by `InspectorSplitHandle`: a 3pt `surface-container-low` line centred in a 9pt hit area with the column-resize cursor; a double click resets the width. Width and open state are persisted. Closed by default. Laid out only in a full window (1100 or wider): a compact window never shows it.
- Pane: `surface-container-lowest` at 72%, left hairline `outline-variant` at 55%. Every tone in it is walked against opaque `surface-container-lowest`; nothing else in it has a hue.
- Header: 44 tall to line up with the chrome, padding 0 14, bottom hairline `outline-variant` at 55%; a 16px `insights` in `on-surface-variant`; `space-sm`; *Activity* in `chrome` 13 / 600 `on-surface`; two compact icon buttons — `open_in_full` 15px (*Open the full Activity screen*) and `close` 16px (*Close inspector  ⌥I*).
- Queue rows (up to 8): padding 14 × 11, bottom hairline `surface-container-low` at 90%; a 17px service mark (`ServiceKey.icon`, `CupolaServices`) in `on-surface-variant` — monochrome, the mark's shape says which service — 11pt; the title in `chrome` 12 / 500 `on-surface`, one line; when the item has a progress, a 3pt bar 5pt below (radius 2, track `surface-container-highest`, value `primary`, or the row's walked tone when it carries a warning); the second line (the episode, its title and the release, or the service and a year: prose with a name in it) in `chrome` 11 `dim-text` in the text face, 5pt below.
- Did not answer (only when a service has every connection dark; a connection that answered with a refusal or a fault is never named here): a quiet line, padding 14, **no fill and no border** (the Presence Rule) — a 15px `cloud_off` in `error` walked against the pane (`statusToneColor`), `space-sm`, then the title in the same red, `chrome` 12 / 600: *Sonarr did not answer* (or the names, *Sonarr and Prowlarr did not answer*); 4pt; *Anything it holds is missing from this list.* (*they* for several) in `chrome` 11 / 500 `dim-text`; `space-xs`; two text buttons in ink — *Retry* (it re-probes every connection of those services and re-reads the queue) and *Settings* (→ *Settings › Connections*). One sentence for a screen reader: the title and the body.
- Finished today (up to 6, only once the history feed has something from today; the local day of `finishedTodayProvider`, the one Activity's band reads): padding 14 at the sides and bottom; the section label, then 30-tall rows of a 7px dot in the event's walked tone (imported green, a failed import amber, grabbed neutral), `space-sm`, and the title in `chrome` 11 / 500 `dim-text`.
- Section labels: the micro role (`AppTheme.chrome`, 11 / 600 / 14, the role's own tracking), in sentence case (*Finished today*), in `dim-text`, `space-sm` above and below.

States: loading *Reading the queue…*; empty *Nothing downloading right now.*, which names what it could not count when an \*arr connection failed (*Nothing downloading right now. Sonarr Anime not counted.*); failed *The queue could not be read. Open Activity to retry.* whenever no \*arr connection answered, not only when the load itself threw, and ahead of any request rows that did arrive — each a `chrome` 12 note in `dim-text`, padding `space-lg`. The did-not-answer line and Finished today follow the note in every state.

The consumer provides nothing: the pane reads the Activity providers (`globalNowItemsProvider`, `unreachableServicesProvider`, and `finishedTodayProvider` over `globalHistoryFeedProvider`). Everything in it also exists on `/activity` (the pane is an accelerator, never the only home of a feature). Toggle ⌥I; ⌥⏎ in the command deck opens it.

## Do / don't

- Do keep every figure here also on `/activity`.
- Don't open the pane by default: reading Finished today starts the history feed.
- Red on the did-not-answer line is correct: those services did not answer. It stays on the glyph and the title; don't give the line a fill or a border, and don't use it for anything that did answer and refused.
