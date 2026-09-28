# WindowChrome

The desktop window's top two strips: the chrome (window buttons, the breadcrumb that is the window title, three chips) and under it the service deck (where you are, the stack at a glance, and the way to anything).

Hand-written from `lib/features/shell/presentation/desktop/window_chrome.dart` and `lib/features/shell/presentation/desktop/service_deck.dart`, with `desktop_window.dart`, `shell_breadcrumb.dart`, `shell_shortcuts.dart` and `stack_health.dart`. Instance names, hosts and counts are illustrative.

Chrome strip:

- 44 tall, 38 when compact (window under 1100 — so 960 is compact); padding 0 `space-md`; bottom hairline `outline-variant` at 55%. The whole strip is a drag region; its buttons win the hit test.
- macOS reserves a 72pt leading gutter for AppKit's own traffic lights (drawn by the OS, never by us; shown as a dashed box). Windows and Linux reserve nothing and draw their own caption buttons.
- Breadcrumb (`AppTheme.chrome` 12): ancestors 500 in `dim-text` and are links (underline on hover), the leaf 600 in `on-surface`; 13px `chevron_right` in `dim-text`, 2pt either side. Spoken as one sentence (*Dashboard, Radarr, Library*).
- Chips, `space-sm` apart: 28 tall (26 compact), padding 0 `space-md`, `radius-md` (the interactive radius, kept when lit), 1px `outline`, 14px glyph then 6; label `chrome` 11 600 `on-surface-variant`; shortcut `chrome` 11 mono in `dim-text`, 6 after the label (after the glyph's 6, a further 4 when compact). Hover wash `on-surface` at 6%. Lit: the owner's accent at 14% with a 40% border, glyph and label in `on-surface`.
  - *Lens: 4K* — a readout, not a button, only when the current service's active connection has a name; `dns` outlined, lit in the service accent.
  - *Refresh all ⌘R* and *Inspector ⌥I* — real buttons; the inspector chip is lit in `nav-activity` while the pane is open.
  - Compact drops every label and keeps glyph and key (the lens keeps only its glyph).
- Keys print `⌘ ⌥ ⇧` on Apple platforms and `Ctrl+`, `Alt+`, `Shift+` elsewhere.

Deck strip (starts right of the 56pt rail):

- 52 tall, 40 compact; padding 0 `space-lg` (`space-md` compact); bottom hairline `outline-variant` at 55%.
- The deck carries the fleet, not the room: no accent wash, no bloom, no accent border. The room light lives on the service header below it (`ServiceTabBar.header`: accent 12% over `surface`, a 30% bloom in its lower 11px).
- Active chip — only when the page does not name the room. On a service's tab root the tab row is the header (`ServiceTabBar.header`: mark, name, lens), so the deck drops the chip; a pushed page (a detail, a wizard) and the canonical tabs keep it. 32 tall (26 compact, max 120 wide), padding `space-sm` / 11, `radius-md`, the service accent at 13% with a 40% border; the 16px service mark (`ServiceKey.icon`, `CupolaServices`) walked with `onTint` at 0.13 against `surface`; `space-sm`; the service title `chrome` 13 600 (12 compact) in `on-surface`; full layout adds the connection name 2pt after it in mono 11, walked accent. On a canonical tab it reads *All services* with `grid_view` in `primary`. Then `space-lg` (`space-sm` compact).
- Health readout — the stack as one figure, at every width (the seventeen-glyph bands are gone: twelve or more accents in the window's highest-contrast band broke the Room Light Rule, and every connection is one ⌘K away). 30 tall (26 compact), padding 0 10, `radius-sm2`, `surface-container`, 1px `outline-variant`; 7px dots, 3 apart (`success` walked against `surface`, a neutral `on-surface-variant` one while anything is checking, `error` walked if anything is down), `space-sm`, answering count `chrome` 12 mono `on-surface`, 3, *`/ 16`* 11 500 `dim-text`, and — unless the deck is under 500pt — 5 then *· 3 down* 11 500 in `error` walked against `surface-container`. Spoken as the stack sentence (*13 of 16 answering · 3 unreachable · 1 not set up*).
- Then a spacer, and — only once the window has been refreshed, and not under 500pt — `ShellFreshness`: *Refreshed 2 min ago* (`chrome` 11 500 `dim-text`, bucketed to the minute: *just now*, *N min ago*, *N h ago*; re-aged every 30 s). It is the one fact the retired status bar owned. `space-lg` (`space-sm` compact) either side.
- Jump pill: a field in shape only — 30 tall (26 compact), padding 0 `space-md` (`space-sm`), `radius-md`, `surface-container-highest` at 55% (80% on hover), 1px `outline-variant`; 14px search glyph, *Jump to anything* (*Jump* compact; under 500pt of deck only the key, 6 after the glyph) and the key, all `dim-text`, 9pt gaps. It opens **CommandDeck**.

Windows and Linux (what the OS switch is allowed to change: button placement, gutter, modifier):

- Windows: three 44-wide caption buttons (`remove`, `crop_square`, `close`, 15px, `on-surface-variant`), no gap, square; hover `on-surface` at 8%, Close hover a full `error` fill with an `ink-on-bright` glyph. They request 44 tall, so the 38 compact strip clamps them.
- Linux (GNOME): 26pt round buttons 8 apart, `surface-container-highest` at 60%, 13px glyphs; Close hover `error` at 24%.
- Both sit `space-md` after the last chip and inside the strip's `space-md` right padding.

## Do / don't

- Do keep every per-OS difference to button placement, gutter width and modifier label.
- Don't light the deck: on a service tab root it shows no service accent at all, and on a pushed page the only accent is the active chip's. The fleet is a count here and a list on ⌘K.
- Don't round the chips to `radius-full`; that shape means a tag or a piece of metadata.
