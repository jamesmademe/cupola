# NavPillTransition

The floating bar changing destination: the selected pill slides and resizes to the new item, the item bumps to 1.02, its label is revealed by a growing clip — and the whole bar can be tugged a few points and snaps back elastically.

Hand-written from `lib/core/widgets/floating_bottom_nav_bar.dart` at text scale 1.0, with the four `NavTab` destinations. Geometry is computed as the widget does, from the measured `labelMedium` w600 label: selected width = 14 × 2 + 20 + 6 + label + 6 (min 84, :747), compact items 52 (:564), gap 6 or 4 below a 360 bar, spare width shared 60/40 (:227), pill 36 tall (:751). The readout prints the resolved widths.

What moves, all on `emphasizedCurve` = `easeOutCubic` unless noted:

- **Item widths**: `AnimatedContainer` per item, `durationSm` 200ms (:468).
- **Pill**: `AnimatedPositioned` 200ms (:541) — only left/width move. Its fill (the accent at 16% dark / 13% light, :512) and border (27%, :533) are a plain `DecoratedBox`, so the **colour snaps** to the new destination's accent on the first frame while the geometry glides.
- **Scale bump**: `AnimatedScale` 1.0 → 1.02 on the selected item, `durationXs` 100ms (:878).
- **Icon**: `AnimatedSwitcher` 200ms keyed on `isSelected` (:904) — outlined glyph fades out as the filled one fades in, linear, each in its own colour.
- **Label**: `AnimatedSize` 200ms, `centerLeft` (:920). On select the label is there at once and the clip grows to reveal it; on deselect the child becomes `SizedBox.shrink()` at once, so the old label vanishes and only its empty space shrinks away.
- **Label colour**: `ServiceTheme.onTint(accent, surface, tint 0.16 / 0.13)`, the same helper the static card uses.
- **Elastic drag** (the bar without a vertical delegate): each drag delta is scaled by `0.15 ÷ (1 + |offset| ÷ 30)` (:218, :221, :247) and the offset is clamped to ±15 on each axis (:215). On release it tweens back to zero over `durationXl` 500ms on `Curves.elasticOut` (period 0.4) (:234, :288) — a curve, not a physics spring, which is why it overshoots a fixed number of times whatever the release speed. The pan starts after the pan slop (2px mouse, 36 touch) and the slop is swallowed, as `DragStartBehavior.start` does. On the phone shell the vertical axis belongs to the Portal instead (see **ServicePortalPhysics**); only `dx` keeps this elastic.
- **Haptic**: one `HapticFeedback.selectionClick()` per tap, fired by the shell (`shell_screen.dart:280`), deliberately not by the bar.

**Reduce Motion**: the widget never reads the setting. Flutter scales every one of these controllers to 5% (`animation_controller.dart:651`): 200 → 10ms, 100 → 5ms, the 500ms spring-back → 25ms. So under Reduce Motion the pill, label and icon arrive in about a frame, and a tugged bar snaps home almost at once; the drag itself still follows the pointer. The switch sets exactly those durations.

Web rendition limits: label width comes from canvas `measureText` with Inter, not `TextPainter`, so widths can differ by a fraction of a point; no haptics; the bar has no backdrop blur here — and neither does the app's (it paints `glassSurface` over `AppElevation.glass`).

Do let the shell own the haptic. Don't animate the pill's colour on top of its geometry — the snap is how the code behaves today.
