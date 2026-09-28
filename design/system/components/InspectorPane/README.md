# InspectorPane

The desktop window's right-hand column: the live queue, who is not answering, and what finished today, without leaving the page you are on.

Hand-written from `lib/features/shell/presentation/desktop/inspector_pane.dart` and `lib/features/shell/domain/inspector_state.dart`. Titles and second lines are illustrative.

- Width 360 by default, 300–520, dragged by a 9pt split handle (a 3pt `surface-container-low` line; double-click resets); persisted with its open state. Closed by default. Laid out only in a full window (1100 or wider): a compact window never shows it.
- Pane: `surface-container-lowest` at 72%, left hairline `outline-variant` at 55%. Every tone and accent in it is walked against opaque `surface-container-lowest`.
- Header: 44 tall to line up with the chrome, padding 0 14, bottom hairline; 16px `insights` in `nav-activity` walked; *Activity* `chrome` 13 600 `on-surface`; two compact icon buttons — `open_in_full` 15px (*Open the full Activity screen*) and `close` 16px (*Close inspector  ⌥I*).
- Queue rows (up to 8): padding 11 × 14, bottom hairline `surface-container-low` at 90%; 17px service mark (`ServiceKey.icon`, `CupolaServices`) in its accent walked against the pane (`surface-container-lowest`), 11pt; title `chrome` 12 500 `on-surface`; a 3pt bar (5 above, radius 2, track `surface-container-highest`, value `primary`, or the row's walked tone when it carries a warning); second line `chrome` 11 mono tabular `dim-text`, 5 above.
- Unreachable (only when a service has every connection dark): padding 14; section label, 10pt; a card padded 12 × 11, `radius-md`, `error` at 7% with a 30% border; 15px `warning_amber` in `error` walked against the card's 7% wash over the pane (`statusToneColor`, tint 0.07), names joined by middots in `chrome` 12 600; *No response. Anything they hold is missing from this list.* `chrome` 11 500 `dim-text`; an outlined *Retry* and a text *Settings* (→ *Settings › Connections*).
- Finished today (up to 6, only once the history feed has something): section label, then 30-tall rows of a 7px dot in the event's walked tone (a failed import is amber) and the title in `chrome` 11 500 `dim-text`.
- Section labels: the `eyebrow` role (11 / 600 / 1.2, 1.4 tracking, set uppercase) in `dim-text`, `space-sm` above and below. A screen reader hears the sentence-case source (*Finished today*), not the capitals.

States: loading *Reading the queue…*, empty *Nothing downloading right now.*, failed *The queue could not be read. Open Activity to retry.* — each a `chrome` 12 note in `dim-text`, padding `space-lg`.

The consumer provides nothing: the pane reads the Activity providers. Everything in it also exists on `/activity` (the pane is an accelerator, never the only home of a feature). Toggle ⌥I; ⌥⏎ in the command deck opens it.

## Do / don't

- Do keep every figure here also on `/activity`.
- Don't open the pane by default.
- Red on the unreachable card is correct: those services did not answer. Don't use it for anything that did answer and refused.
