# SearchBarHeader

The always-visible search field at the top of a browsable screen, with the page's accent on the magnifier and a clear button once there is a query.

Rendered from `lib/core/widgets/search_bar_header.dart` (a Material 3 `SearchBar`) by `test/design_catalog/search_bar_header_catalog_test.dart`. Hints are the callers' real strings: *Search movies & TV shows...* (Seerr Discover), *Search torrents...* (qBittorrent), *Movies, shows, artists...* (Search tab), *Search movies...* / *Search TV series...* / *Search artists...* (the library screens); the default is *Search...*.

- Outer padding `AppSpacing.sm` top, `AppSpacing.lg` sides, `AppSpacing.lg` bottom.
- Field: minimum height 52, `surfaceContainer` fill, 1px `outlineVariant` side, `AppRadius.borderRadiusMd` (12) — the radius every input in the theme takes — elevation 0, horizontal padding `AppSpacing.sm`.
- Leading: `AppSpacing.sm`, then a 24pt `search_rounded` glyph in the accent walked against `surfaceContainer` (`ServiceTheme.onTint`, `tintAlpha: 0`). The accent is ink here, so Lidarr's pink and the Search tab's purple are measured, not painted: on the light theme's white field they walk darker until they clear.
- Text and hint are the `SearchBar` defaults: `bodyLarge` in `onSurface`, the hint in `onSurfaceVariant`, with `SearchBar`'s own 8pt either side of the input. A query longer than the field scrolls inside it.
- Trailing, only while there is text: an `IconButton` with a `close_rounded` glyph in `onSurfaceVariant`.
- Input is debounced (`debounceDuration`, 400 ms by default) and trimmed; clearing reports an empty query at once.
- On a desktop window drawing the desktop shell the field registers itself as the screen's ⌘F target (`ScreenSearchTarget`); a phone build takes no provider dependency.

## The consumer provides

`onQueryChanged`, `hintText`, an optional `initialQuery`, `autofocus`, `debounceDuration`, and the `accent` — the page's service or section accent; without one the magnifier takes `primary`.

## Semantics

The field speaks as *Search*, hint *Type &lt;hintText&gt;*. The clear button is one node: button, *Clear search*, hint *Remove the current search query*.

## Do / don't

- Do pass the page accent so the magnifier says whose search this is.
- Don't round the field into a pill — that is the metadata shape.
- Don't debounce again in the caller; the value arrives settled.
