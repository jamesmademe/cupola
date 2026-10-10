# WindowChrome

The desktop window's one strip across the top: the window buttons, the breadcrumb that is the window title, on Activity who of its sources answered and when, the way to anything (⌘K) and the inspector's switch.

Rendered from `lib/features/shell/presentation/desktop/window_chrome.dart` (with `lib/core/platform/desktop_window.dart`, `shell_breadcrumb.dart`, `shell_shortcuts.dart` and the answer line of `lib/features/activity/domain/activity_readout.dart`) by `test/design_catalog/window_chrome_catalog_test.dart`. Connection names and counts are sample data. The sheet is drawn on macOS, so the Windows and Linux caption buttons described below are not on it.

There is no second strip under it. What the deck strip used to carry went to where it is read: the room to the sidebar's lit row and the page's own header, the stack's health to the sidebar's lights, the Home's line and Stack, the way to anything to this strip.

- `WindowChrome.height` 44, `compactHeight` 38 in a window under 1100 (so 960 is compact); padding 0 `space-md`; bottom hairline `outline-variant` at 55%. Its words grow with the reading size up to 1.3, as the sidebar's do, and no further: the strip's height is the window's.
- The strip's ground is the drag region (`_DragSurface`): it moves the window, and a double click on it zooms it as the OS's title bar does. The controls lie over the ground as its siblings, never its children, so a click on one is never held for the double-click timeout; the title and the gaps take no pointer, so the window drags from them.
- macOS reserves a 72pt leading gutter for AppKit's own traffic lights (drawn by the OS, never by the app). Windows and Linux reserve nothing and draw their own caption buttons.
- Breadcrumb (`AppTheme.chrome` 12, one line each, ellipsised): ancestors 500 in `dim-text` and are links (underline on hover; a tap goes to that place), the leaf 600 in `on-surface`; a 13px `chevron_right` in `dim-text` between them, each crumb and chevron padded 2pt either side. Spoken as one sentence (*Stack, Radarr, Library*). A title's page under a tab names its kind (*Discover › Movie*, *Series*, *Person*, *Collection*), never a place it is not.
- Then, right-aligned, each `space-sm` to `space-md` from the next:
  - *Lens: 4K* — a readout, not a button, shown only when the current service has two connections, naming the one the page reads by the app's one rule (`SettingsModel.connectionName`: the user's name, else *Radarr 2* from its place; never a label a single connection kept from a sibling since removed). 28 tall (26 compact), padding 0 `space-md`, `radius-md`, the room's strong fill (`fill-strong`) under a 1px `outline`: a choice in force. A 14px `dns` outlined then 6 and the label in `chrome` 11 / 600, all `on-surface`; compact keeps the glyph alone. Its tooltip: *Showing Radarr · 4K. Change it from the deck.*
  - **The answer line**, on Activity's pages only (`activityAnswerLine`): who of the sources Activity reads answered, the same sources the Home's banner counts (`dashboardDecisionsProvider`), and when the last did (`activityAnsweredAtProvider`, by the device's clock): *All 12 answered at 20:53*. While the slowest are out, *9 of 12 answered*; before any answered, *Asking 12*. In `chrome` 12 / 500 tabular `dim-text`; when a source did not answer the line turns red (walked against `surface`) with a 6pt dot before it (*11 of 12 answered*), amber when one answered with a fault. It is a button: a click asks every source again, as ⌘R does, and its tooltip says *Ask again ⌘R*, under who did not answer and why (`coverageFailureSentence`). Underlined on hover. Spoken as the line, with who did not answer, and the hint *Ask again*. The other pages have no answer line until their surface decides one.
  - **The way to anything** (`_JumpField`): a field in shape only, 240 wide (its words' width compact), 30 tall (26 compact), padding `space-row` then `space-xs`, `radius-md`, `surface-container-highest` at 55% (80% on hover), 1px `outline-variant`; a 14px search glyph, *Jump to…* (*Jump* compact) in `chrome` 12 / 500 `dim-text`, and the key `⌘K` in `chrome` 11 mono `dim-text` on a cap of `on-surface` at 6%, `radius-xs`. Its target is at least 44 wide and the strip's height. It speaks *Jump to anything, ⌘K* with the hint *Open the command deck*, and opens **CommandDeck**.
  - **The inspector's switch**: a 34 × 28 control (`radius-md`, 1px `outline`) with a 16px `view_sidebar` in `on-surface-variant`; on while the pane is open: the room's strong fill under `on-surface`, monochrome as the sidebar's selection is. Hover wash `on-surface` at 6%. Its target is 44 wide and the strip's height. Tooltip *Inspector ⌥I*; spoken *Inspector, ⌥I*, a button with a toggled state. Only in a full window: a compact window never lays the pane out, so it has no switch for it.
- **The requester's chrome** is the breadcrumb alone: no way to anything (her window has no command deck) and no inspector (what it follows is the stack's activity, the operator's).
- Keys print `⌘ ⌥ ⇧` on Apple platforms and `Ctrl+`, `Alt+`, `Shift+` elsewhere.

Windows and Linux (what the OS switch is allowed to change: button placement, gutter, modifier):

- Windows: three 44-wide caption buttons (`remove`, `crop_square`, `close`, 15px, `on-surface-variant`), no gap, square; hover `on-surface` at 8%, Close hover a full `error` fill with an `on-error` glyph. They request 44 tall, so the 38 compact strip clamps them.
- Linux (GNOME): 26pt round buttons `space-sm` apart, `surface-container-highest` at 60%, 13px glyphs; Close hover `error` at 24%.
- Both sit `space-md` after the last chip and inside the strip's `space-md` right padding. Each is a button named *Minimize*, *Maximize*, *Close*.

`WindowDragStrip`, in the same file, stands in for the chrome above a flow the shell does not host (onboarding): the same height and gutter, the caption buttons where the OS needs them, and a trail (*Cupola › Setup*) in `chrome` 11 / 500 `dim-text` throughout, because none of its crumbs is a link. It draws nothing on a phone.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- `WindowChrome` full inside Radarr on its 4K connection (the lens, the way to anything, the switch off); on Activity with the inspector open (the answer line, the switch on); on Activity with a source that did not answer (the line in red); compact; the requester's window; `WindowDragStrip`.
- Text at 200%: the chrome on Activity.

## Do / don't

- Do keep every per-OS difference to button placement, gutter width and modifier label.
- Don't light the strip: the only fills on it are the lens and the switch while on, both the room's strong fill. Colour on it is information: the answer line's red or amber, never a section's or a service's.
- Don't put a control inside the drag ground: lay it over the ground, or every click on it waits for the double click.
- Don't round the chips to `radius-full`; that shape means a tag or a piece of metadata.
