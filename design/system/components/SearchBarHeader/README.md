# SearchBarHeader

The always-visible search field at the top of a browsable screen, with the page's accent on the magnifier and a clear button once there is a query.

Hand-written from `lib/core/widgets/search_bar_header.dart` (a Material 3 `SearchBar`). Hints are real: *Search movies & TV shows...* (Seerr), *Search torrents...* (qBittorrent), *Movies, shows, artists...* (Search tab); the query is illustrative.

- Outer padding `space-sm` top, `space-lg` sides, `space-lg` bottom.
- Field: min height 52, `surface-container`, 1px `outline-variant`, `radius-md` (12px), the radius every input in the theme takes, elevation 0, inner padding `space-sm`.
- Leading: `space-sm`, then a 24px `search` glyph in the accent walked against `surface-container` (`onTint`, tint 0) — the accent is ink here, so Lidarr's pink and the `nav-search` purple are measured, not painted.
- Text `body-large` in `on-surface`; hint `body-large` in `on-surface-variant`; `space-sm` either side of the input.
- Trailing, only with text: a 48px `close` button in `on-surface-variant`.
- Input is debounced 400ms and trimmed; clearing reports an empty query at once. On a desktop window the field registers as the screen's ⌘F target.

The consumer provides `onQueryChanged`, `hintText`, an optional `initialQuery`, `autofocus` and the accent (the page's service or section accent; default `primary`).

Speaks as *Search*, hint *Type &lt;hint&gt;*; the clear button speaks *Clear search*, hint *Remove the current search query*.

Do pass the page accent so the magnifier says whose search this is. Don't round the field into a pill — that is the metadata shape.
