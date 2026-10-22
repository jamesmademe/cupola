# PosterFlight

The shared-element flight from a grid poster to the detail page's poster slot: the page slides in underneath while the poster flies over both, lifted to level-3 at the midpoint and set down at level-2.

Hand-written from `lib/core/widgets/media_poster_card.dart` (`flightShuttleBuilder`), the route page in `lib/core/utils/route_utils.dart` and `media_detail_view.dart`, plus the Flutter 3.47.7 framework pieces they rely on. Artwork: `__POSTER__`, `__BACKDROP__`. Tap any poster; the back button pops.

- **Route**: detail routes are `CupertinoPage`s (`route_utils.dart:13`), so the push runs over Cupertino's `kTransitionDuration`, **500ms** (`cupertino/route.dart:155`), not an app token. The incoming page slides from the right on `fastEaseInToSlowEaseOut`, the grid shifts a third left on `linearToEaseOut`; the pop uses the flipped curve and `easeInToLinear` (`route.dart:535–541`).
- **Flight**: the Hero's animation is the route's on `Curves.fastOutSlowIn` = `cubic-bezier(0.4, 0, 0.2, 1)`, flipped for the pop (`widgets/heroes.dart:464`). Its path is a `MaterialRectArcTween` (MaterialApp's hero controller, `material/app.dart:802`): two opposite corners each travel along a circular arc, which is why the poster curves rather than sliding straight. Both ends are measured inside their own routes, ignoring the page slide, so the poster lands on the slot's final position while the page is still arriving.
- **Lift**: the shuttle is the destination's `MediaPosterCard`. Its shadow is `BoxShadow.lerpList(level2, level3, easeOut(lift))` with `lift = 1 − |2a − 1|` (`media_poster_card.dart:142–147`): level-2 at both ends, level-3 at the midpoint, symmetric for push and pop. Resting posters are level-2 too (:122), so nothing pops at take-off or landing.
- **Destination settle**: behind the flight the detail backdrop fades in and eases from 1.06 to 1.0 on the route animation through `emphasizedCurve`, `Cubic(0.2, 0.8, 0.2, 1)` (`media_detail_view.dart:706–711`).
- **Sections**: a view mounted mid-push holds its section cascade for the route's duration (:113), then each section fades and rises 16pt over 320ms, 45ms apart (`StaggeredEntrance`, `staggered_entrance.dart:41–55`).
- The plot draws page slide, flight and lift against route time; the line marks the current frame.

**Reduce Motion**: the shuttle builder returns the static level-2 poster, no lift (`media_poster_card.dart:129`); the settle and the section cascade are skipped. The route itself is not special-cased: Flutter runs its controller at 5% (`animation_controller.dart:651`), so push and pop last 25ms; the page and poster land in about two frames.

Web rendition limits: the flight is a positioned overlay in one frame, not a separate route overlay; Cupertino's edge shadow on the incoming page is approximated by a fixed soft shadow; the back-swipe gesture (`transitionOnUserGestures`) is not ported. *Slow ×4* stretches the clock only.

Do keep the resting poster at level-2 so the flight starts and ends where it sits. Don't give the source and destination different shadows or radii.
