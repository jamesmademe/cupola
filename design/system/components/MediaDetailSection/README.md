# MediaDetailSection

The detail body's spine: six regions in one fixed order, each labelled by an accent eyebrow the page cannot forget, with fields edited in place on value rows.

Hand-written from `lib/core/widgets/media_detail_slot.dart` (`MediaDetailBody`, `MediaDetailSlot`), `media_detail_section_label.dart`, `media_detail_value_row.dart` and the emitter `_emitBody` in `media_detail_view.dart`.

- **Order** — `deck` → `readout` → `operate` → `synopsis` → `reference` → `related`. A page omits a region; it never reorders one. Region 3 (the manifest: the file, seasons, albums, the request ledger) sits above the prose on purpose. Region 5's internal order: Details, Where to watch, Scores, then Genres / Keywords / Tags. Region 6: Cast, Collection, Filmography.
- **Rhythm (owned by the spine, never by a caller)** — deck: `space-lg` under the hero, never labelled. Readout: `space-md` under the deck, unlabelled, a rail that bleeds off the trailing edge. Every labelled slot: `space-xl` above the label, `space-sm` below it — the asymmetric proximity is the grouping; no dividers, no boxes. An unlabelled slot still buys `space-xl` above it. Horizontal inset: the `space-lg` gutter, a column capped at 720 (`bodyMaxWidth`); a `track` slot (tables) runs the full width at the plain gutter.
- **Label** — the region name uppercased for the eye (`eyebrow`, 11 / 600, +1.4), in the page accent walked by `onTint` against `surface` at alpha 0, up to two lines. Optional count: `space-sm`, `body-small` tabular in `dim-text`, one line, ellipsised. Optional trailing control after `space-sm` (Bazarr's 20px `refresh` icon button, tooltip *Refresh from Bazarr*); past 1.4× reading size the control drops under the label with `space-xs`.
- **Value row** — min height 44, `space-xs` vertical padding. Label in `label-small` 600 `on-surface-variant` (one line), 2px, value in `body-small` 600 `on-surface` (two lines). Editable: an 18px `expand_more` in `on-surface-variant`; a tap opens one bottom sheet for that one field on a phone (*Quality profile* — *Currently HD-1080p*), a menu anchored to the row on a desktop window. Writing: a 16px, 2px-stroke spinner replaces the chevron and the row takes no taps. Unanswered: the value reads `—` in `dim-text`, never blank or zero. No write behind it: a plain fact, no chevron, no button role.
- Two-track desktop layout (≥ `bp-content-well`, desktop shell only): slots named in `sideTrack` stand in a 380 column; deck and readout never move.

The consumer provides `MediaDetailBody` with slots (`.box`, `.lazy` sliver, `.rail`), each with a sentence-case `label`, optional `count` and `labelAction`. Service accents and sample values are illustrative; the dashed blocks are schematic, not widgets.

Semantics: each label is one header node speaking the original-case name and count (*Seasons, 41 of 48 on disk*); a trailing control keeps its own node. A value row is one button: name, value, then the caller's hint (*Changes it on Radarr*).

Do: pass labels in sentence case (`'Missing subtitles'`) and omit an empty slot entirely. Don't: pad a slot yourself, or pass a pre-uppercased label — it is read out shouting.
