# PressableScale

The press feedback on every tappable card, poster and row: a 0.96 dip while the finger is down, and a light haptic when the tap lands.

Hand-written from `lib/core/widgets/pressable_scale.dart`. The poster uses `__POSTER__`; the row is a stand-in AppCard.

- **The dip**: `AnimatedScale` to `pressedScale` 0.96 (`AppAnimation.pressScale`, :53) over `AppAnimation.press` 180ms (:88) on `standardCurve` = `Cubic(0.2, 0.8, 0.2, 1)` (:89). Release goes back to 1.0 on the **same** 180ms ease. It is a tween both ways, not a spring: nothing overshoots.
- **When it starts**: the scale follows `onTapDown`. Inside a scroll view (where nearly every PressableScale lives) the tap competes with the scroll gesture, so Flutter holds `onTapDown` until `kPressTimeout`, 100ms after the finger lands. The card ports that: hold, and the dip starts at 100ms. A tap shorter than 100ms fires down and up in the same frame, so **no dip is painted at all**; only the haptic. Moving more than `kTouchSlop` (18) cancels (`onTapCancel`): the tile returns and no haptic fires.
- **Haptic**: `HapticFeedback.lightImpact()` on `onTap` (:75), after the finger lifts, when `haptic` is true (the default). The dashed chip lights when it would fire.
- *Play a tap* holds the poster for 420ms and lets go. *Slow ×10* stretches the 180ms so the curve can be seen; the press timeout stays real.

**Reduce Motion**: `animate = !MediaQuery.disableAnimationsOf(context)` (:84). The target stays 1.0 and the duration is `Duration.zero`; the dip is removed, not shortened. The haptic is unchanged, and so are the semantics (label, value, hint, button role).

Web rendition limits: no haptics on the web (the chip stands in); the dip is a CSS transition on the compositor rather than a Flutter frame; the press timeout is a `setTimeout`, so it can drift by a frame.

Do keep the default 0.96; it reads as depth. Don't wrap an element that already has a hover/press treatment of its own.
