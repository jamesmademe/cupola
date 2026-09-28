# AppBottomSheet

The one sheet chrome in the app: drag handle, optional accent header, a body that scrolls, on a lifted panel that rises from the bottom edge.

Hand-written from `lib/core/widgets/app_bottom_sheet.dart` (`AppSheetHandle`, `AppSheetHeader`, `AppBottomSheet`), shown through `lib/core/utils/sheet_utils.dart`.

## Anatomy

- **Panel**: `surface-container` in both themes (the widget paints it itself, so light is white), top corners `radius-lg`, `level-3`, clipped. Shown on the root navigator above the floating nav bar, scroll-controlled, safe-area aware, padded by the keyboard inset; the barrier is black at 54%. Min-content sheets cap at 92% of the screen height.
- **Handle**: 36 × 4, `radius-full`, `on-surface-variant` at 35%, `space-sm` above and below.
- **Header** (only when `title` is non-empty): padding 0 / `space-lg` / `space-md` (top `space-md` when the handle is hidden). Optional 40 × 40 tile, `radius-md`, accent at 14%, 20px glyph in the accent walked against its tile over `surface-container` (`ServiceTheme.onTint`, tint 0.14), `space-md` to the text. Title `title-large` 600, two lines max; subtitle `body-small` `on-surface-variant`, `space-xs` below, two lines max. Optional `headerTrailing`, then an optional close `IconButton` (`close`, full 48 target, platform close tooltip).
- **Accent glow**: with `accent` set, a radial wash behind the top 140pt — accent at 22% fading to 0, centred top, radius 1.1 × the short side (`AppGradients.serviceGlow`).
- **Body** padding `space-lg` / 0 / `space-lg` / `space-lg`; `.showScrollable` passes zero and hands the builder the sheet's `ScrollController`.

## Variants

- `.show` — min-content forms and pickers; the body scrolls internally so the keyboard can never overflow it. Shown: Sonarr's *Series type* picker and qBittorrent's *Add torrent* form.
- `.showScrollable` — drag-to-resize list (`DraggableScrollableSheet`, 0.6 initial / 0.4 min / 0.95 max). Every branch of its body must attach the given controller or drag-to-close stops working. See ReleaseRow for the Interactive search sheet.

## The consumer provides

Title, subtitle, icon, accent, trailing, and the body. Option rows and form content are the caller's: in the picker (`series_type_row.dart`) the selected label is `body-large` 600 in the accent walked against the surface, with a 20px check; the Add torrent submit is the caller's `FilledButton` in the qBittorrent accent, minimum height 46.

## Semantics

The sheet adds none of its own; the header reads as its text, and the close button carries the platform close tooltip.

## Do / don't

- Do give every sheet that belongs to a service its accent, so the glow and tile say whose sheet it is.
- Do walk any accent ink against the sheet's own ground.
- Don't build a second sheet chrome.
- Don't leave a `.showScrollable` branch unattached to its controller.
