# NavPillTransition

The floating bar changing destination: the selected pill slides and resizes to the new item, the item bumps to 1.02, its label is revealed by a growing clip — and the whole bar can be tugged a few points and snaps back elastically.

Hand-written from `lib/core/widgets/floating_bottom_nav_bar.dart` at text scale 1.0, with the four `NavTab` destinations. Geometry is computed as the widget does, from the measured `labelMedium` w600 label: selected width = 14 × 2 + 20 + 6 + label + 6 (min 84, :751), compact items 52 (:557), gap 6 or 4 below a 360 bar, spare width shared 60/40 (:231), pill 36 tall (:755). The readout prints the resolved widths.

What moves, all on `emphasizedCurve` = `Cubic(0.2, 0.8, 0.2, 1)` unless noted:

- **Item widths**: `AnimatedContainer` per item, `durationSm` 320ms (:472).
- **Pill**: `AnimatedPositioned` 320ms (:535) — only left/width move. Its fill is the room's strong fill (`CupolaRoom.fillStrong`: white at 12% dark, ink at 12% light, :527) on a plain `DecoratedBox` with no edge (:545) — the same in every section, so there is no colour to change: only the geometry glides.
- **Scale bump**: `AnimatedScale` 1.0 → 1.02 on the selected item, `durationXs` 180ms (:868).
- **Icon**: `AnimatedSwitcher` 320ms keyed on `isSelected` (:895) — outlined glyph fades out as the filled one fades in, linear, each in its own ink.
- **Label**: `AnimatedSize` 320ms, `centerLeft` (:911). On select the label is there at once and the clip grows to reveal it; on deselect the child becomes `SizedBox.shrink()` at once, so the old label vanishes and only its empty space shrinks away.
- **Ink** (:836): the selected icon and label in the primary ink (`onSurface`), the rest in the secondary ink (`onSurfaceVariant`) — monochrome, as the static card is.
- **Elastic drag** (the bar without a vertical delegate): each drag delta is scaled by `0.15 ÷ (1 + |offset| ÷ 30)` (:222, :225, :251) and the offset is clamped to ±15 on each axis (:219, :281). On release it tweens back to zero over `durationXl` 520ms on `Curves.elasticOut` (period 0.4) (:238, :292) — a curve, not a physics spring, which is why it overshoots a fixed number of times whatever the release speed. The pan starts after the pan slop (2px mouse, 36 touch) and the slop is swallowed, as `DragStartBehavior.start` does. On the phone shell the vertical axis belongs to the Portal instead (see **ServicePortalPhysics**); only `dx` keeps this elastic.
- **Haptic**: one `HapticFeedback.selectionClick()` per tap, fired by the shell (`shell_screen.dart:279`), deliberately not by the bar.

**Reduce Motion**: the widget never reads the setting. Flutter scales every one of these controllers to 5% (`animation_controller.dart:651`): 320 → 16ms, 180 → 9ms, the 520ms spring-back → 26ms. So under Reduce Motion the pill, label and icon arrive in about a frame, and a tugged bar snaps home almost at once; the drag itself still follows the pointer. The switch sets exactly those durations.

Web rendition limits: label width comes from canvas `measureText` with Onest, not `TextPainter`, so widths can differ by a fraction of a point; no haptics; the bar has no backdrop blur here — and neither does the app's (it paints `glassSurface` over `AppElevation.glass`).

Do let the shell own the haptic. Don't give the pill a colour per section — it is the same strong fill everywhere, which is why only its geometry moves.
