# NavPillTransition

The floating bar changing destination: the pill slides to the new column, the glyphs cross-fade, and the whole bar can be tugged a few points and snaps back elastically.

Hand-written from `lib/core/widgets/floating_bottom_nav_bar.dart` at text scale 1.0, with the operator's four `NavTab` destinations (Home · Discover · Activity · Stack) and their glyphs: Material Icons outlined at rest and rounded when lit, Activity's pulse line from Material Symbols (`Symbols.vital_signs`, outlined at rest, rounded when lit). Geometry is the widget's: the bar is as wide as the page less 16 a side (`AppSpacing.lg`, :384), `barHeight` 62 (`size.tabbar`, :76) with a 1pt border and `surfacePadding` 5 (:85), so the columns share the inside width equally (:422) and the pill fills the lit column, as tall as the inside (:428–434). Each column is the 20pt glyph (:482) over its name in `labelMedium` (12/16, w500, w600 when lit, :509), 2 apart (:485). The readout prints the resolved columns and pill.

What moves, all on `emphasizedCurve` = `Cubic(0.2, 0.8, 0.2, 1)` unless noted:

- **Pill**: `AnimatedPositioned` over `durationSm` 320ms (:428): only its left moves, since every column has one width. Its fill is the room's strong fill (`CupolaRoom.fillStrong`: white at 12% dark, ink at 12% light) with no edge, tinted by the light of the room in front where there is one (`RoomSheen`, :400); these cards stand under the lamp, so the fill is plain.
- **Icon**: `AnimatedSwitcher` 320ms keyed on `isSelected` (:563): the outgoing glyph fades out as the incoming one fades in, linear, each in its own ink.
- **Name**: no animation. Its ink and weight change on the frame of the tap (:529, :582): the primary ink (`onSurface`) at w600 when lit, the secondary ink (`onSurfaceVariant`) at w500 otherwise.
- **Elastic drag** (the bar without a vertical delegate): each drag delta is scaled by `0.15 ÷ (1 + |offset| ÷ 30)` (:238, :241, :261) and the offset is clamped to ±15 on each axis (:235, :290). On release it tweens back to zero over `durationXl` 520ms on `Curves.elasticOut` (period 0.4) (:248, :300): a curve, not a physics spring, which is why it overshoots a fixed number of times whatever the release speed. The pan starts after the pan slop (2px mouse, 36 touch) and the slop is swallowed, as `DragStartBehavior.start` does. On the phone shell the vertical axis belongs to the Portal instead (see **ServicePortalPhysics**); only `dx` keeps this elastic.
- **Haptic**: one `HapticFeedback.selectionClick()` per tap, fired by the shell (`shell_screen.dart:445`), deliberately not by the bar.

**Reduce Motion**: the widget never reads the setting. Flutter scales every one of these controllers to 5% (`animation_controller.dart:651`): 320 → 16ms, the 520ms spring-back → 26ms. So under Reduce Motion the pill and the glyph arrive in about a frame, and a tugged bar snaps home almost at once; the drag itself still follows the pointer. The switch sets exactly those durations.

Web rendition limits: names are laid out by the browser with Onest, not `TextPainter`, so an ellipsis can fall a fraction of a point apart; no haptics; the bar has no backdrop blur here, and neither does the app's (it paints `glassSurface` over `AppElevation.glass`).

Do let the shell own the haptic. Don't give the pill a colour per section; it is the same strong fill everywhere, which is why only its position moves.
