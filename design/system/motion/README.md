# Motion

The app's motion, animated. A still picture cannot show a curve or a spring, so these ten cards are
the one place the design system re-draws the app instead of rendering it: each `preview.html` plays
the real durations, curves and spring constants, read from the Dart source named in its README, and
honours Reduce Motion the way Flutter does (animations run at 5% of their duration; springs and
repeats stop).

Because they are re-drawings, they can drift. When the motion code changes, change the card with it:
the constants are named in both places.

`motion.css` and `motion.js` (the port of `ServiceTheme.onTint` / `foregroundOn` that lets a label
resolve its contrast the way the app does) are shared by the cards; colours and sizes come from the
generated tokens. `python3 tool/design_system/gallery.py --serve` plays them in dark and light.

Icons are Material Icons (`.cp-icon`, `.cp-icon.outlined`), as in the app. A glyph only Material Symbols
has, such as Activity's pulse line (`vital_signs`), takes `.cp-icon.symbols` (outlined) or `.cp-icon.symbols.rounded`,
and its card loads that family with `icon_names`, so only the glyphs it draws are fetched.

| Card | Source |
| --- | --- |
| [DetailHeroCollapse](DetailHeroCollapse/README.md) | `lib/core/widgets/media_detail_view.dart` |
| [MotionTokens](MotionTokens/README.md) | `lib/core/app_animation.dart` |
| [NavPillTransition](NavPillTransition/README.md) | `lib/core/widgets/floating_bottom_nav_bar.dart` |
| [PosterFlight](PosterFlight/README.md) | `lib/core/widgets/media_poster_card.dart` |
| [PressableScale](PressableScale/README.md) | `lib/core/widgets/pressable_scale.dart` |
| [ReelLine](ReelLine/README.md) | `lib/core/widgets/reel_line.dart` |
| [ServicePortalPhysics](ServicePortalPhysics/README.md) | `lib/features/shell/presentation/service_portal.dart` |
| [ServiceRingMotion](ServiceRingMotion/README.md) | `lib/core/widgets/service_ring.dart` |
| [ShimmerSweep](ShimmerSweep/README.md) | `lib/core/widgets/shimmer_placeholder.dart` |
| [StatusBadgeAnimated](StatusBadgeAnimated/README.md) | `lib/core/widgets/status_badge.dart` |
