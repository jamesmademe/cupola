# SearchBarHeader

The always-visible search field at the top of a browsable screen: a monochrome magnifier and a clear button once there is a query.

Rendered from `lib/core/widgets/search_bar_header.dart` (a Material 3 `SearchBar`) by `test/design_catalog/search_bar_header_catalog_test.dart`. Hints are the callers' real strings: *Movies, series, artists* (the Discover tab; *Movies and series* for the requester), *Search torrents* (qBittorrent), *Search movies* / *Search series* / *Search artists* (the library screens); the default is *Search*. No hint ends in an ellipsis.

- Outer padding `AppSpacing.sm` top, `AppSpacing.lg` sides, `AppSpacing.lg` bottom.
- Field: minimum height 52, `surfaceContainer` fill, 1px `outlineVariant` side, `AppRadius.borderRadiusMd` (14) — the control radius; the theme's own text fields take the 16 field radius — elevation 0, horizontal padding `AppSpacing.sm`. Focused, the side is 1.5px `line.focus`, as every focused field's is, so the keyboard's place is never only a caret.
- Leading: `AppSpacing.sm`, then a 24pt `search_rounded` glyph in `on-surface-variant` (the secondary ink), on every screen — spaced for the field's own fill in both themes. It used to take the page's service or section colour.
- Text and hint are the `SearchBar` defaults: `bodyLarge` in `onSurface`, the hint in `onSurfaceVariant`, with `SearchBar`'s own 8pt either side of the input. A query longer than the field scrolls inside it.
- Trailing, only while there is text: an `IconButton` with a `close_rounded` glyph in `onSurfaceVariant`.
- Input is debounced (`debounceDuration`, 400 ms by default) and trimmed; clearing reports an empty query at once.
- On a desktop window drawing the desktop shell the field registers itself as the screen's ⌘F target (`ScreenSearchTarget`); a phone build takes no provider dependency.

## The consumer provides

`onQueryChanged`, `hintText`, an optional `initialQuery`, `autofocus` and `debounceDuration`. No colour: the field is the same field whichever service it searches.

## Semantics

The field speaks as *Search*, hint *Type &lt;hintText&gt;*. The clear button is one node: button, *Clear search*, hint *Remove the current search query*.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- Empty with a hint (the Discover tab, qBittorrent, Lidarr), with a query, with a long query that scrolls inside the field.
- `autofocus: true`: the field holding focus, on the phone and on the desktop.
- A long hint on a 320pt phone, ellipsised inside the field.
- Text at 200%: the hint and a query.

## Do / don't

- Do let the hint say what is searched (*Search artists*); the glyph says nothing about whose search it is.
- Don't round the field into a pill — that is the metadata shape.
- Don't debounce again in the caller; the value arrives settled.
