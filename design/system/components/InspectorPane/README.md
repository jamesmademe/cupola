# InspectorPane

The desktop window's right-hand column, for the thing you chose: a download picked in Activity's table, without leaving the page you are on.

Rendered from `lib/features/shell/presentation/desktop/inspector_pane.dart` (`InspectorPane`, `InspectorSplitHandle`) and `lib/features/shell/domain/inspector_state.dart` by `test/design_catalog/inspector_pane_catalog_test.dart`; the download's page inside it is the DownloadDetail card's. Titles and release names are sample data.

It used to stand open with the queue in it, a third of the window that most of the time said *Nothing downloading right now*. The queue now sits folded at the foot of the sidebar ([DesktopNavRail](../DesktopNavRail/README.md), In flight), and the pane opens only on a choice.

- **When**: a download is chosen in [DownloadTable](../DownloadTable/README.md) (a click, or the arrow keys walking the rows), the window is 1100 or wider, and the pane is switched on. Choosing switches it on. With nothing chosen it is not laid out at all, and its switch in the window strip is dimmed and inert (*Inspector, nothing chosen*; tooltip *Inspector: choose a download in Activity*). ⌥I hides and shows it while a download is chosen, and does nothing otherwise. The choice lasts while the app runs, so a download chosen in Activity stays beside the pages you go on to.
- Width `InspectorState.defaultWidth` 360, clamped to 300–520, dragged by `InspectorSplitHandle`: a 3pt `surface-container-low` line centred in a 9pt hit area with the column-resize cursor; a double click resets the width. Width and the switch are persisted.
- Pane: `surface-container-lowest` at 72%, left hairline `outline-variant` at 55%.
- Header: 44 tall to line up with the window's strip, padding 0 14, bottom hairline `outline-variant` at 55%; a 16px `download` in `on-surface-variant`; `space-sm`; *Selected download* in `chrome` 13 / 600 `on-surface`; two icon buttons at the theme's standard density (40pt, the desktop's pointer floor): `open_in_full` 15px (*Open the download's page*) and `close` 16px (*Close  ⌥I*), which puts the choice down and the pane with it.
- Under it, the download's page in the pane's column (`DownloadPage.inspector`, [DownloadDetail](../DownloadDetail/README.md)): no room and no way back, inset 14, the steps two to a line. Removing the download from there puts the choice down.
- Kept current by the reads that keep the queue current: the sidebar's In flight away from Activity, Activity's own poll on it.

The consumer provides nothing: the pane reads the choice (`selectedDownloadProvider`) and the queue. Everything in it also exists on `/activity/download` (the pane is an accelerator, never the only home of a feature).

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- A stuck download chosen in the table, beside the split handle.
- Text at 200%: the same.

## Do / don't

- Do keep every fact here also on the download's page.
- Don't open the pane with nothing chosen, and don't put the queue back in it: the queue is In flight.
