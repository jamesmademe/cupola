# FaultBand

The quiet line above a page's content that says something is wrong — glyph, sentence, recovery verb — while the last readout below it stays at full ink.

Hand-written from `lib/core/widgets/fault_band.dart`.

## Anatomy

- A line, not a card: no fill, no border. Padding `space-xs` vertical, `space-lg` leading, `space-sm` trailing; glyph-to-text gap `space-sm`.
- Glyph 16px, the only coloured thing on the line (**the presence rule**). Its tone is walked against `surface` through `statusToneColor`, because with no fill behind it the glyph is the whole signal.
- Sentence `body-small` in `on-surface-variant`, filling the row.
- Verbs are text buttons in `primary` — never the fault tone — `label-large`, horizontal padding `space-sm`, minimum 56 × 44. No compact density.

## Variants

| Constructor | Tone | Glyph | Sentence | Verbs |
|---|---|---|---|---|
| `.unreachable` | `error` | `cloud_off` | *TrueNAS did not answer. Everything below is what it said last.* — with `since` ≥ 1 minute: *TrueNAS has not answered for 6 minutes. …* | Retry · Settings (optional) |
| `.section` | `error` | `link_off` | The caller's sentence, naming which source inside the service did not answer and what is missing | Retry · Settings (optional) |
| `.stale` | `warning` | `history_toggle_off` | *These figures are 6 min ago.* + the caller's detail; under a minute *These figures have stopped updating.* | Refresh only, no dismiss |
| `.offlinePush` | `error` | `cloud_off` | *Radarr stopped answering while this page was open. Everything here is the last render; a write will fail until it is back.* | Retry · Open Radarr (optional) |

## The consumer provides

The service name (or, for `.section`, the whole sentence), the stale `age` and `detail`, and the callbacks. Actions are a label and a callback (`FaultBandAction`), never a widget, so a caller cannot restyle the verb.

## Semantics

The band is one container node labelled with the sentence and marked as a live region, so it is announced when it appears. The glyph and text are excluded; each verb stays its own control.

## Do / don't

- Do keep the page below the band at full ink: nothing is dimmed for being unreachable — dimming means *not configured*.
- Do pair `.section` with `ServiceKpi.unavailable` so the figures that source owns read `—`, never `0`.
- Don't paint Retry red or add a dismiss to `.stale`: a stale reading is still true after it is acknowledged.
- Don't use it where the retry lives elsewhere (a form's submit button) — that is `FaultNote`.
