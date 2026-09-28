**The Lit Control Room.** Cupola is a dark operator's console for a self-hosted media stack and its infrastructure — seventeen services, one native client, five platforms. The room stays quiet and near-black; the service being operated supplies the light. Radarr brings amber, Sonarr violet, TrueNAS utility blue. That tint is orientation, not decoration: it says where you are before you read a title.

Calm at rest, tactile on touch, honest when something breaks. The product is a Flutter app; these rules, the tokens and the pictures its own widgets render (the design catalog) are its specification, and every value here is the one the code ships. The values themselves live in `design/tokens/` and are generated into the app and into `tokens.json` — edit them there, never here.

## Content fundamentals

- **English only, on purpose.** No localisation layer; copy is written once, in plain English.
- **Sentence case everywhere** — section headers, buttons, tabs, empty-state titles: `Needs attention`, `Pool health`, `No results found`, `Not set up`. Uppercase appears only in the `eyebrow` style (`QUEUE`, `MISSING`, `NOT ANSWERING`), set by transforming the text.
- **Name the service, not the mechanism.** `Open in qBittorrent`; *Sonarr lists nothing under Specials yet.* A cross-service control whose target is not configured stays tappable and names the service in its hint.
- **The lexicon is fixed.** `Answering` / `Not set up` / `Retry` / relative ages as `2 h ago`. A stack line counts itself in: `13 of 16 answering · 3 unreachable`.
- **Facts are joined with a middot** and hair spaces: `Cupola 1.0.0 · Apache-2.0`, `Last known · 12 min ago`.
- **A figure nobody could read is an em dash, never `0`.** `0` asserts the queue is empty; `—` says the source did not answer. Never count inside a capped or paged response and state it as a total.
- **No emoji, no exclamation marks, no marketing voice.** A fault is a whole sentence and a verb: *TrueNAS did not answer. Everything below is what it said last.* — `Retry`. An empty state says what is true and, if useful, what to try: *No results found — Try a different title or spelling.*
- **Promise only what works.** Better to delete a control than ship one that fails.

## Colour

A near-black stage with one saturated light source. Dark is the primary theme; light is a complete parallel palette, not an inversion. Both are fixed constants — platform Dynamic Color is never harmonised in (**The Fixed Palette Rule**).

**The surface ladder.** Six steps, each a distinct tone: `surface` (Room Floor) → `surface-container-lowest` (Sub-floor, recessed wells) → `surface-container-low` (Riser) → `surface-container` (Panel: cards, sheets, dialogs) → `surface-container-high` (Raised Panel) → `surface-container-highest` (Instrument Face: inputs, chips). Text is `on-surface`, then `on-surface-variant`, then `dim-text` — three steps, never more. Borders use `outline` and are scarce.

**The tone rule — five arms, a closed set.**

| Tone | Token | Means | Never means |
|---|---|---|---|
| Green | `success` | available, complete | — |
| Amber | `warning` | a **fault**: failing, stalled, errored, stopped unexpectedly, expiring | missing, wanted, paused |
| Red | `error` | **unreachable**, and nothing else (one exception below) | failed download, missing file, a rejected release |
| Blue | `info` | queued, informational — including a request awaiting approval | — |
| Neutral | `on-surface-variant` | the **backlog**: missing, wanted, cutoff unmet, not aired, deliberately paused, deleted | — |

**The one exception is an action, never a status.** A destructive confirmation — the Delete fill, its glyph, its *cannot be undone* line — is red, because red on an action means irreversible. It never leaks back into status: a rejected release, a negative custom-format score or a failed import is not red.

Painting the backlog amber is the commonest way this breaks: in a media stack a list of things to fetch is the resting state, not damage. Something stopped on purpose is neutral; only an unexpected exit is amber. Every status also carries a word or icon — colour is never the only channel.

**Fill byte vs. ink.** `success`, `warning`, `info` and `error` are *fill* values — dots, poster overlays, 10–16% washes. As text they go through `statusToneColor(scheme, tone, surface:, tintAlpha:)`, which walks the tone's lightness until it clears 4.6:1 on the ground it actually lands on. Raw `warning` on paper is ~1.4:1. Never paint a status token as text directly.

**Service accents** (`seerr` … `plex`) are identity, not health. Each is measured against every other accent and every status tone before adoption — `transmission` and `plex` were walked off their brand values to stay distinguishable at 8px.

- **The Room Light Rule.** One service accent lights a screen. Only the three all-services objects — the Dashboard, the ⌘K deck and the ServiceRing — show every accent at once, confined to each service's own glyph, node or low-alpha wash.
- **The Luminance Rule.** A label on an opaque accent takes `ServiceTheme.foregroundOn(accent)` — white or `ink-on-bright`, whichever measures higher (white on `radarr` is 2.15:1). An accent label on its own tint takes `ServiceTheme.onTint(accent, surface:, tintAlpha:)`, resolved against the surface the chip sits on (usually `surface-container-high`), in **both** themes.
- **The Contained Fill Rule.** A fill that carries words walks until white or ink clears 4.5:1; for the brand that means `primary-container`, not raw `primary`.
- **The Bounded Light Rule.** The ambient radial wash is at the ceiling contrast allows, so it cannot say which room you are in. On desktop the service header — the tab row that names the service — does: the current accent at 12% across the band and a bloom rising to 30% in its lower 11px, below the text; the selected tab's own accent rule is the edge, so there is no second accent line. The deck above it is a fleet-wide readout and wears no service colour.
- **Plates** (`plate-*`) stand in for artwork and are dark in both themes — a missing poster is not a white hole on paper.
- **Navigation accents** (`nav-activity`, `nav-search`, `nav-settings`) belong to app sections. They stay out of the status hues so permanent chrome never reads as a health signal.

## Typography

One family does the work: **Inter**, bundled as a variable font (`wght` 100–900, `opsz` 14–32). Code, logs, YAML and certificate fingerprints use the `mono` stack (Menlo first — never the bare `monospace` alias, which is proportional on Apple platforms).

- Set running text in `body-medium`; long prose in `body-large` capped at 640px.
- A row that is a *name* uses `row-title`; the answer in a dense row uses `data`, which sits above `label-medium` on purpose — the thing that needs a human is never smaller than the word describing it.
- `subtitle` names the service in its own app bar; `panel-header` heads a region inside a page.
- **The 11px floor.** `label-small` is the minimum anywhere. Where geometry can't take 11px, the geometry grows.
- **The Weight Ceiling Rule.** 800 is for display only; headlines and the app-bar title stop at 700; everything else stops at 600. The one exception is a KPI figure at 700.
- **Tracking is derived, not authored**: Inter's curve (`-0.0223 + 0.185·e^(-0.1745·size)` em), plus +0.006em on dark below 24px. The `eyebrow` (+1.4px, uppercase) is the one authored value.
- **Leading ladder.** Display tightens to 1.10 (the floor — accented capitals collide below it), body opens to 1.45–1.55, labels stay at ~1.22.
- Numbers that update in place use tabular figures; code uses slashed zero.

## Layout and spacing

A 2px step with a 4px rhythm on top. `space-lg` (16px) is the page gutter and card padding; `space-md` (12px) the grid and carousel gap; `space-xl` (24px) separates sections; `space-xxl` (32px) major blocks. The half-steps `space-xxs`, `space-s`, `space-m`, `space-ml` live inside components only. A value off the 2px grid is a defect.

- Screens are single-column and scroll vertically under a transparent app bar with a gradient scrim.
- Media grids use a 130px preferred tile and resolve their real column count from the width — the declared count is a floor.
- Detail bodies stop at 720px; prose at 640px; the desktop content well at `bp-content-well`.
- **The Reduction Rule.** A narrower window shows fewer items at full size — never smaller ones. No token has a compact twin.
- Text boxes grow with the reading size (compact chrome clamps at 1.6×, single-line chrome at 1.3× and elides). Touch targets are 48px minimum (44pt on iOS) for anything a finger can reach — compact density may not shave them. Pointer-only desktop chrome (the desktop rail, the deck, window-chrome rows) may go to 38–40px.
- Phones are portrait only. Tablets are not a design target.

## Shape

Rounded rectangles. `radius-md` (12px) is the default for cards, buttons, inputs, posters and snackbars. `radius-sm` for badges and small objects; `radius-lg` for dialogs and sheet tops; `radius-xl` for the floating nav bar.

- **The Pill-for-Metadata Rule.** `radius-full` means a tag, genre or rating — never an interactive container.
- `radius-pill` (20px) belongs to navigation and to rows of choices — segments, filter chips, pickers — and a row keeps it in **both** states: selection is carried by fill, border and ink, never by the corner.
- **The Permeable Edge Rule.** Prefer a tint or scrim to a stroke. When a border is needed, `outline` or a low-alpha accent.
- Status dots are 8px circles; empty-state wells are 72px (52px compact).

## Elevation and depth

Material tonal elevation is not used. Flat is the default (**The Earned Elevation Rule**); a surface earns a shadow only when it must read as a lifted object.

- `level-1` resting cards, rows, KPI tiles · `level-2` posters and `AppCard.elevated` · `level-3` sheets, popovers, hero surfaces · `glass` the floating nav bar only.
- **The Two-Shadow Rule.** Every level is a contact shadow plus an ambient one. Light theme shadows are ink (`#111827`), not black.
- **The No-Blur-Under-Scroll Rule.** Nothing blurs the content behind it: the floating nav bar is a semi-opaque `glass-surface` tint (not a backdrop filter), and heroes and scrolling bars deepen a gradient scrim instead.
- A single signature card may carry one service glow (accent radial at 0.22); repeated cells use a fraction of that.

## Motion

Durations: 100ms micro (ripples), 200ms state changes, 300ms standard transitions, 400ms complex, 500ms dramatic. Standard curve is emphasized ease-in-out-cubic; entering elements ease out cubic. Shimmer cycles in 1500ms; a success check holds 1600ms before reverting.

Motion answers an action or a meaningful state change. Dense cards dip to 0.97 scale with a light haptic on press; posters fly between list and detail as shared elements (level-2 → level-3 → level-2). The ServiceRing sweep (96s) runs only when the ring is the subject. Everything decorative stops under Reduce Motion.

## Failure states

Unreachable and unconfigured are normal daily conditions. Four levels, one vocabulary:

- **Unreachable** — the page keeps its identity, tabs and last-known readout under a `Last known · 12 min ago` rule. Last-known data keeps full-strength ink (**The Full Ink Rule**).
- **Section** — one source inside a service failed: only that section falls back, and its figures read `—`.
- **Stale** — the poll stopped returning: `warning`, no dismiss, rows trade time-left for sample age.
- **Offline push** — a pushed page whose service died keeps its last render; only live search says so.

**The Presence Rule.** A fault is a quiet line — glyph, sentence, recovery verb, dismiss. No fill, no border, the error tone on the glyph alone. The recovery verb is `primary`, never red: a red Retry makes the cure look like the disease. **Dimming means a precondition is unmet** — the other service is not set up here, or the saved credential may not make this change — and never that a service is unreachable. A dimmed control stays tappable, keeps its 44pt target, says what it needs in its hint, and answers a tap with a toast whose one verb is the fix.

## Credential scope

A credential can work and still not be allowed to write: an Unraid or TrueNAS key without write scope, a view-only Nginx Proxy Manager account. The app asks once, on connect, what the key may do, and remembers the answer per connection; a refused write teaches it too. Nothing is broken, so nothing is amber:

- **The banner** is one quiet blue line at the top of the page — glyph, sentence, one verb (`Update the key`, `Change account`, or `Check again` when the app could not ask). It is a standing fact, not an event, so it is not announced on every visit.
- **Every write stays on the page**, dimmed but tappable, in the same cell a cross-service jump uses. Its hint says what it needs; its toast leads to that connection's settings.
- **Settings** names the scope beside the connection: `Answering · read-only key` (or `view-only account`).
- A Jellyfin account that is not an administrator gets a calm *Needs a Jellyfin administrator* note on the tabs it cannot read, instead of an error.

## Accessibility

Binding, not best effort. WCAG AA in both themes, checked against the ground each colour actually lands on. Dynamic Type never clips. VoiceOver and TalkBack operate everything: a row speaks one sentence and silences its parts; status is spoken, not only coloured; a dimmed control is never announced as disabled. The focus ring is a 2px `primary` border.

## Iconography

Two families, and they never swap roles.

- **Service marks** — each service is drawn with its own mark from the `CupolaServices` font (U+E001–U+E011; SVG sources in `tool/service_glyphs/svg/`, usage in `assets/README.md`). A mark identifies a service and nothing else. It takes the service's accent, walked with `onTint` against its soft container (accent at 14%), and it never carries a status. TrueNAS, Unraid and Plex are deliberately not their logos (trademark policy): a drive rack, a hard disk, a film strip.
- **Interface glyphs** — Flutter's Material Icons, **rounded** variant, for everything that is not a service: actions, states, navigation on phones. The outlined variant is the unselected pose of a navigation destination (`monitor_heart` outlined → rounded when Activity is selected). The **desktop rail** alone draws Material Symbols Rounded at weight 300, because Material Icons' single stroke reads heavier than the type beside it on a desktop.

No emoji, no custom illustration. The brand mark — the cupola seen from above, six lit panes around a round window — lives in `assets/brand/` (usage in `assets/README.md`). It is never redrawn, recoloured or placed on a light ground without its dark body.

## Do and don't

- **Do** pair `AmbientScaffold` with the current service accent and a `GlassAppBar`.
- **Do** read every value from a token; never a widget-local literal for size, spacing, radius, duration or accent ink.
- **Do** draw the failure state of anything you draw the healthy state of.
- **Don't** use a service hue to communicate health, or let two accents light a service screen.
- **Don't** set text in a bare `TextStyle(fontSize:)` — it never reaches the `wght` axis and renders Regular. Use a role and `.weight()`.
- **Don't** blur behind scrolling content, use a single shadow as depth, or a full-radius pill for a button.
- **Don't** add a per-OS skin — no Cupertino on iOS, Fluent on Windows or Adwaita on Linux. The OS owns safe areas, gestures, window buttons and the modifier key; nothing else.
