# DetailHeroCollapse

The media detail hero folding away under the finger: a 236-tall stage of artwork, room light and poster row shrinks to a 52-tall glass title bar as the body scrolls, with the scrim deepening as the art gives way to chrome.

Hand-written from `lib/core/widgets/media_detail_view.dart` (`_MediaDetailHeaderDelegate`, `_MediaDetailHeader`), `media_detail_header_metrics.dart` (`MediaDetailHeroPhase`), `app_gradients.dart` (`heroScrim`, `serviceGlow`), `media_detail_back_button.dart` and `glass_app_bar.dart`. Static anatomy is on the **MediaDetailHero** card. Artwork: `__BACKDROP__`, `__POSTER__`; the room light is Radarr's.

Nothing here runs on a clock. The header is a pinned sliver laid out at `max(52, 236 − scroll)`; every value below is a function of one progress `t = (236 − height) ÷ 184`:

- **Extents**: 236 expanded (`media_detail_header_metrics.dart:21`), 52 collapsed (:24), both plus the top safe area (0 in this frame) and both grown with reading size (1.0 here).
- **Scrim**: `heroScrim(surface, depth: seg(t, 0, 0.80))` (:133) — bottom-up `surface` → `surface` at `lerp(0.85, 1, depth)` at 0.35 → `surface` at `lerp(0, 0.35, depth)` at the top (`app_gradients.dart:29–32`). At full collapse the middle is opaque and the top holds 35%. A 16pt seam below the art fades `surface` to nothing.
- **Parallax**: the art group is kept at full height and moved up by `t × 184 × 0.35` (`media_detail_view.dart:739`, metrics :146).
- **Room light**: `serviceGlow(accent, topRight, radius 1.3, alpha)` with alpha `0.22 → 0.12` over t 0.30–0.75 (:150; view :682). It lives inside the art group, so it scrolls away with the art.
- **Poster row**: glued to the rising bottom edge plus an exit push, `bottom = 16 − t × 184 × 0.7` (`_posterExitFactor`, view :656), scaled 1 → 0.86 from the bottom-left over t 0.20–0.90 (metrics :139). Never faded — it is a Hero source.
- **Glass bar**: opacity `barReveal = easeOutCubic(seg(t, 0.62, 0.92))` (metrics :136, view :842); `GlassSurface` is a gradient, `surface` 55% → 28% at 0.55 → clear (light 60/32, `glass_app_bar.dart:33–34`), no blur.
- **Back button**: plate `surface` at 0.62 held until `barReveal` 0.82, then released to nothing (`media_detail_back_button.dart:118`, :130); top eases from 12 to (52 − 48) ÷ 2 = 2 (:188).
- **Title hand-off**: the hero title never fades — the poster row slides under the bar. What hands off is semantics: the row is excluded and the bar title becomes the spoken header at `barReveal ≥ 0.5` (view :823). The readout names the owner.
- *Scroll demo* scrolls 120, then 260, then back.

**Reduce Motion** (`MediaDetailHeroPhase(reduceMotion:)`): parallax factor 0, poster scale held at 1, exit factor 1.0 (the row moves at exactly content speed), and the overscroll stretch is switched off (view :559). Scrim, bar reveal, glow and back-button plate still track the finger, because they are the legibility story, not decoration. The destination settle behind the poster flight is also skipped (see **PosterFlight**).

Web rendition limits: no bouncing overscroll, so the stretch is not shown; the header is an overlay repainted on `scroll` + `requestAnimationFrame`, not a sliver; top safe area 0.

Do let the scrim carry legibility. Don't blur the backdrop or wrap the poster row in an `Opacity`.
