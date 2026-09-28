# AppBottomSheet

The one sheet chrome in the app: drag handle, optional accent header, a body that scrolls, on a lifted panel that rises from the bottom edge.

Rendered from `lib/core/widgets/app_bottom_sheet.dart` (`AppSheetHandle`, `AppSheetHeader`, `AppBottomSheet`) by `test/design_catalog/app_bottom_sheet_catalog_test.dart`; shown through `lib/core/utils/sheet_utils.dart`. The catalog draws each panel as it stands open, over the modal barrier.

## Anatomy

- **Panel**: `surfaceContainer` in both themes (the widget paints it itself, so light is white), top corners `AppRadius.lg` (16), `AppElevation.level3`, clipped. `SheetUtils.showCupolaModalSheet` shows it on the root navigator (above the floating nav bar), scroll-controlled and safe-area aware; the panel pads itself by the keyboard inset and keeps its content inside the bottom safe area. The barrier is Material's default, black at 54%. A min-content sheet caps at 92% of the screen height. On a wide window Material centres the sheet and caps it at 640pt.
- **Handle** (`AppSheetHandle`, `showHandle`, on by default): 36 × 4, `AppRadius.borderRadiusFull`, `onSurfaceVariant` at 35%, `AppSpacing.sm` above and below.
- **Header** (`AppSheetHeader`, only when `title` is non-empty): padding `AppSpacing.lg` at the sides, `AppSpacing.md` below, 0 above — `AppSpacing.md` when the handle is hidden. Optional 40 × 40 tile, `AppRadius.borderRadiusMd`, the accent at 14%, a 20pt glyph in the accent walked against its tile over `surfaceContainer` (`ServiceTheme.onTint`, `tintAlpha: 0.14`), `AppSpacing.md` to the text. Title `titleLarge` at 600, two lines at most; subtitle `bodySmall` in `onSurfaceVariant`, `AppSpacing.xs` below, two lines at most — it is where a service-supplied media title lands. Then an optional `headerTrailing`, then an optional close `IconButton` (`close_rounded`, the platform close tooltip, `maybePop`). Without an accent the tile takes `primary`.
- **Accent glow** (only with `accent` set): a radial wash behind the top 140pt — the accent at 22% (`opacityServiceGlow`) fading to 0, centred at the top, radius 1.1 (`AppGradients.serviceGlow`).
- **Body**: `bodyPadding`, by default `AppSpacing.lg` / 0 / `AppSpacing.lg` / `AppSpacing.lg`; `.showScrollable` passes zero.

## Variants

- `AppBottomSheet.show` — min-content forms and pickers. The body sits in a `SingleChildScrollView`, so the keyboard can never overflow it. Callers: the one-field value pickers (`showMediaValueSheet`, e.g. *Quality profile*, subtitle *Currently HD-1080p*), Sonarr's *Series type*, qBittorrent's *Add torrent* form.
- `AppBottomSheet.showScrollable` — a drag-to-resize list in a `DraggableScrollableSheet` (0.6 initial / 0.4 min / 0.95 max). The builder receives the sheet's `ScrollController`, and every branch of its body must attach it or drag-to-close stops working. See ReleaseRow for the Interactive search sheet.
- Both take `isDismissible` and `enableDrag`.

## The consumer provides

Title, subtitle, icon, accent, trailing, close, and the body. Option rows and form content are the caller's: `MediaValueOptionRow` draws a picker option with an 18pt `check_circle_rounded` / `circle_outlined` and a `bodyLarge` label, 600 and in the accent walked against the surface when selected, 500 otherwise; the Add torrent submit is the caller's `FilledButton` in the qBittorrent accent, minimum height 46.

## Semantics

The sheet adds no node of its own; the header reads as its text, and the close button carries the platform close tooltip.

## Do / don't

- Do give every sheet that belongs to a service its accent, so the glow and tile say whose sheet it is.
- Do walk any accent ink against the sheet's own ground.
- Don't build a second sheet chrome.
- Don't leave a `.showScrollable` branch unattached to its controller.
