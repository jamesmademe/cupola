# WindowChrome

The desktop window's top two strips: the chrome (window buttons, the breadcrumb that is the window title, the chips) and under it the service deck (where you are, the stack at a glance, and the way to anything).

Rendered from `lib/features/shell/presentation/desktop/window_chrome.dart` and `lib/features/shell/presentation/desktop/service_deck.dart` (with `shell_freshness.dart`, `lib/core/platform/desktop_window.dart`, `shell_breadcrumb.dart`, `shell_shortcuts.dart` and `stack_health.dart`) by `test/design_catalog/window_chrome_catalog_test.dart`. Connection names and counts are sample data. The sheet is drawn on macOS, so the Windows and Linux caption buttons described below are not on it.

Chrome strip (`WindowChrome`):

- `WindowChrome.height` 44, `compactHeight` 38 in a window under 1100 (so 960 is compact); padding 0 `space-md`; bottom hairline `outline-variant` at 55%. The whole strip is a drag region; its buttons win the hit test.
- macOS reserves a 72pt leading gutter for AppKit's own traffic lights (drawn by the OS, never by the app). Windows and Linux reserve nothing and draw their own caption buttons.
- Breadcrumb (`AppTheme.chrome` 12, one line each, ellipsised): ancestors 500 in `dim-text` and are links (underline on hover; a tap goes to that place), the leaf 600 in `on-surface`; a 13px `chevron_right` in `dim-text` between them, each crumb and chevron padded 2pt either side. Spoken as one sentence (*Dashboard, Radarr, Library*).
- Chips, `space-sm` apart: 28 tall (26 compact), padding 0 `space-md`, `radius-md` (the interactive radius, kept when lit), 1px `outline`; a 14px glyph then 6; label `chrome` 11 / 600 `on-surface-variant`; shortcut `chrome` 11 mono in `dim-text` (a key legend, not a figure), 6 after the label (4 after the glyph when compact). Hover wash `on-surface` at 6%. On: the room's strong fill (`fill-strong`) under the same 1px `outline`, glyph and label in `on-surface` — monochrome, never a section's or a service's colour. A button chip's hit area is the strip's full height.
  - *Lens: 4K* — a readout, not a button, shown only when the current service has two connections, naming the active one by the app's one rule (`SettingsModel.connectionName`: the user's name, else *Radarr 2* from its place; never a label a single connection kept from a sibling since removed); `dns` outlined, on (a choice in force); its tooltip says *Showing Radarr · 4K. Change it from the deck.*
  - *Refresh all ⌘R* and *Inspector ⌥I* — real buttons; the inspector chip is on while the pane is open.
  - Compact drops every label and keeps glyph and key (the lens, which has no key, keeps only its glyph).
- Keys print `⌘ ⌥ ⇧` on Apple platforms and `Ctrl+`, `Alt+`, `Shift+` elsewhere.

Deck strip (`ServiceDeck`, starts right of the 56pt rail):

- `fullHeight` 52, `compactHeight` 40; padding 0 `space-lg` (`space-md` compact); bottom hairline `outline-variant` at 55%.
- The deck carries the fleet, not the room: no wash, no bloom, no border of the room's light. The room light lives on the service header below it (`ServiceTabBar.header`).
- Active chip — only when the page does not name the room. On a service's tab root the tab row is the header (mark, name, lens), so the deck drops the chip; a pushed page (a detail, a wizard) and the canonical tabs keep it. 32 tall (26 compact, capped at 120 wide), padding `space-sm` left and 10 right, `radius-md`, the service's accent — the lamp — at 13% with a 40% border; the 16px service mark (`ServiceKey.icon`, `CupolaServices`) through `onTint` at 0.13 against `surface`, which resolves the lamp to the primary ink; `space-sm`; the service title `chrome` 13 / 600 (12 compact, ellipsised) in `on-surface`; the full layout adds the connection name 2pt after it in `chrome` 11 (the text face: it is the user's own word), in the same ink, only when the service has two connections; a name derived from the connection's place (*Radarr 2*) already says the service and is the title itself, with no second name. On a canonical tab it reads *All services* with `grid_view` in `primary`, on a `primary` wash. Then `space-lg` (`space-sm` compact). Spoken *Viewing Radarr, 4K*, or *All services*.
- Health readout — the stack as one figure, at every width; every connection is one ⌘K away. 30 tall (26 compact), padding 0 10, `radius-control` (14), `surface-container`, 1px `outline-variant`; 8px dots, 2 apart (`success` walked against `surface`, a neutral `on-surface-variant` one while any probe is checking, `error` walked if anything is down), `space-sm`, the answering count `chrome` 12 tabular `on-surface` (a figure: text face, never mono), 2, *`/ 16`* 11 / 500 `dim-text`, and — unless the deck is under 500pt — 4 then *· 3 down* 11 / 500 in `error` walked against `surface-container`. Spoken as the stack sentence (*13 of 16 answering · 3 unreachable · 1 not set up*).
- Then a spacer, and — only once the window has been refreshed, and not under 500pt — `ShellFreshness`: *Refreshed 2 min ago* (`chrome` 11 / 500 `dim-text`, bucketed: *just now*, *N min ago*, *N h ago*; re-aged every 30 s), with `space-lg` (`space-sm` compact) either side.
- Jump pill: a field in shape only — 30 tall (26 compact), padding 0 `space-md` (`space-sm`), `radius-md`, `surface-container-highest` at 55% (80% on hover), 1px `outline-variant`; a 14px search glyph, *Jump to anything* (*Jump* compact; under 500pt of deck only the key, 6 after the glyph) and the key in mono, all `dim-text`, 8pt gaps. Its target is at least 44 × 44 (44 × 40 compact). It speaks *Jump to anything, ⌘K* with the hint *Open the command deck*, and opens **CommandDeck**.

Windows and Linux (what the OS switch is allowed to change: button placement, gutter, modifier):

- Windows: three 44-wide caption buttons (`remove`, `crop_square`, `close`, 15px, `on-surface-variant`), no gap, square; hover `on-surface` at 8%, Close hover a full `error` fill with an `on-error` glyph. They request 44 tall, so the 38 compact strip clamps them.
- Linux (GNOME): 26pt round buttons `space-sm` apart, `surface-container-highest` at 60%, 13px glyphs; Close hover `error` at 24%.
- Both sit `space-md` after the last chip and inside the strip's `space-md` right padding. Each is a button named *Minimise*, *Maximise*, *Close*.

`WindowDragStrip`, in the same file, stands in for the chrome above a flow the shell does not host (onboarding): the same height and gutter, the caption buttons where the OS needs them, and a trail (*Cupola › Setup*) in `chrome` 11 / 500 `dim-text` throughout, because none of its crumbs is a link. It draws nothing on a phone.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- `WindowChrome` full inside Radarr, on Activity with the inspector open, compact; `ServiceDeck` on a canonical tab, a service's tab root, a pushed page, compact, under 500pt; `WindowDragStrip`.
- Text at 200%: the chrome inside Radarr, and the deck on a pushed page.

## Do / don't

- Do keep every per-OS difference to button placement, gutter width and modifier label.
- Don't light the deck: on a service tab root it shows no chip at all, and on a pushed page the only wash is the active chip's lamp. The fleet is a count here and a list on ⌘K.
- Don't round the chips to `radius-full`; that shape means a tag or a piece of metadata.
