import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/theme.dart';

/// Paints the room behind [child], full-bleed: the ground, and the room's
/// light at the top of it.
///
/// The light is one of two things (brand book, *The title light*). A room led
/// by a title is lit by the title's artwork itself ([art]): the picture,
/// blurred past recognition and saturated, laid over the top of the room and
/// faded into the ground, so the poster's colours spill onto the wall the way
/// a television's light does. Any other room is lit by a lamp: a soft ellipse
/// of [accent] hung at the top centre, the neutral lamp ([AppColors.lamp])
/// when there is none. A room whose picture is still being read is lit by its
/// light's colour, and the picture comes up over it.
///
/// Because the base is opaque, this can sit directly behind a transparent
/// [Scaffold] (and a transparent/glass app bar) so the light reads
/// continuously across the whole screen, including the status-bar and app-bar
/// band.
///
/// **The light drifts, it does not cut.** A change to [accent] is animated
/// over [accentDuration] on the standard curve, the clock the page transition
/// and the onboarding ring's resize run on: three instruments, one beat. A new
/// picture comes up over [AppAnimation.light], as the title's own page does,
/// and the one it replaces fades under it. Reduce Motion removes both
/// animators: the room is simply already lit.
///
/// Nothing here blurs while a page scrolls (the No-Blur-Under-Scroll Rule):
/// the picture was blurred once, small, off the UI isolate (`bakeRoomArt`),
/// and is only scaled up here, in a layer of its own.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final Color? accent;

  /// The picture of the room's light, when a title leads it.
  final RoomArt? art;

  /// How long the light takes to drift to a new [accent]. A room lit by a
  /// title's artwork takes [AppAnimation.light], as the title's own page
  /// does.
  final Duration accentDuration;

  const AmbientBackground({
    super.key,
    required this.child,
    this.accent,
    this.art,
    this.accentDuration = AppAnimation.durationMd,
  });

  @override
  Widget build(BuildContext context) {
    // A room with no light of its own (no picture, and the lamp or nothing)
    // takes the light of the place it stands in: every tab of a service is
    // one room, lit by what leads the service ([RoomLightScope]).
    final scope =
        this.art == null && (accent == null || accent == AppColors.lamp)
        ? RoomLightScope.maybeOf(context)
        : null;
    final art = scope?.art ?? this.art;
    // Resolved *before* the tween, not inside its builder. [accent] is
    // nullable and `ColorTween` asserts on a null `end`. Naming the fallback
    // here is also what makes a screen drift out of and back into the lamp
    // rather than cutting at the edges of a lit stretch.
    final target = scope?.accent ?? accent ?? AppColors.lamp;

    if (MediaQuery.disableAnimationsOf(context)) {
      return _Room(accent: target, art: art, child: child);
    }

    return TweenAnimationBuilder<Color?>(
      // `ColorTween`, not `Tween<Color?>`: only the former knows how to
      // interpolate a colour, and the plain one would snap at the halfway frame.
      tween: ColorTween(end: target),
      duration: accentDuration,
      curve: AppAnimation.standardCurve,
      // The subtree is built once and carried through every frame of the drift:
      // the room repaints, the screen inside it does not rebuild.
      child: child,
      builder: (context, drifting, builtChild) => _Room(
        // `drifting` is null only on the very first frame, before the tween has
        // a begin value; the target is the right answer there too.
        accent: drifting ?? target,
        art: art,
        child: builtChild!,
      ),
    );
  }
}

/// The light of a place several rooms stand in: the tabs of a service, each
/// its own page, lit as one room by what leads the service. A room inside it
/// with no light of its own takes this one ([AmbientBackground]).
class RoomLightScope extends InheritedWidget {
  const RoomLightScope({
    super.key,
    required this.accent,
    required this.art,
    required super.child,
  });

  /// The light's colour, or null for the lamp.
  final Color? accent;

  /// Its picture, or null.
  final RoomArt? art;

  static RoomLightScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomLightScope>();

  @override
  bool updateShouldNotify(RoomLightScope oldWidget) =>
      oldWidget.accent != accent || oldWidget.art != art;
}

/// The room's light, for a widget inside it that has to paint the room again:
/// the fade under a bar (`AmbientScaffold`) and the scrim under the clock
/// (`StatusBarScrim`) cover content with the room itself, light and all,
/// where a flat colour would read as a step wherever the light is.
class AmbientRoom extends InheritedWidget {
  const AmbientRoom({
    super.key,
    required this.scheme,
    required this.accent,
    this.picture,
    this.leaving,
    this.presence = 0,
    required super.child,
  });

  final ColorScheme scheme;

  /// The lamp's light at this frame, drifting when the accent changes.
  final Color accent;

  /// The picture lighting the room, and the one fading out from under it.
  final ui.Image? picture;
  final ui.Image? leaving;

  /// How far [picture] has come up, 0 to 1 (and [leaving] gone down).
  final double presence;

  static AmbientRoom? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmbientRoom>();

  /// Paints the room into [rect], laid out as it is across [room], the
  /// room's whole box, so the patch matches the room around it.
  void paint(Canvas canvas, Rect rect, Rect room) {
    canvas.save();
    canvas.clipRect(rect);
    // The patch's own ground first: what it covers is the patch, not the room.
    canvas.drawRect(rect, Paint()..color = scheme.surface);
    paintRoom(
      canvas,
      room,
      ground: false,
      scheme: scheme,
      accent: accent,
      picture: picture,
      leaving: leaving,
      presence: presence,
    );
    canvas.restore();
  }

  @override
  bool updateShouldNotify(AmbientRoom oldWidget) =>
      oldWidget.accent != accent ||
      oldWidget.scheme != scheme ||
      oldWidget.picture != picture ||
      oldWidget.leaving != leaving ||
      oldWidget.presence != presence;
}

/// Paints a whole room into [room]: the ground, the lamp, and the picture of
/// the light with its scrim. One function for the room and every patch of it,
/// so a patch can never drift from what it covers.
void paintRoom(
  Canvas canvas,
  Rect room, {
  bool ground = true,
  required ColorScheme scheme,
  required Color accent,
  ui.Image? picture,
  ui.Image? leaving,
  double presence = 0,
}) {
  if (ground) canvas.drawRect(room, Paint()..color = scheme.surface);
  final dark = scheme.brightness == Brightness.dark;

  // How much of the room the pictures light, and so how much the lamp gives
  // way: the lamp comes back as the last picture leaves.
  final lit =
      (picture == null ? 0.0 : presence) +
      (leaving == null ? 0.0 : 1 - presence);
  final lamp = (1 - lit).clamp(0.0, 1.0);
  if (lamp > 0) _paintLamp(canvas, room, accent, dark, lamp);
  if (lit <= 0) return;

  final box = RoomLightMetrics.box(room.width);
  final boxRect = Rect.fromLTWH(
    room.left + box.left,
    room.top + box.top,
    box.width,
    box.height,
  );
  final bottom = room.top + RoomLightMetrics.scrimStops.last;
  canvas.save();
  canvas.clipRect(Rect.fromLTRB(room.left, room.top, room.right, bottom));
  for (final (image, strength) in [
    if (leaving != null) (leaving, 1 - presence),
    if (picture != null) (picture, presence),
  ]) {
    _paintPicture(canvas, image, boxRect, strength);
  }
  final alphas = dark
      ? RoomLightMetrics.darkScrimAlphas
      : RoomLightMetrics.dayScrimAlphas;
  final scrim = Rect.fromLTRB(room.left, room.top, room.right, bottom);
  canvas.drawRect(
    scrim,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          // Over the lamp the scrim is ground on ground: it only ever dims the
          // pictures, as far as they light the room.
          for (final alpha in alphas)
            scheme.surface.withValues(alpha: alpha * lit.clamp(0.0, 1.0)),
        ],
        stops: [
          for (final stop in RoomLightMetrics.scrimStops)
            stop / RoomLightMetrics.scrimStops.last,
        ],
      ).createShader(scrim),
  );
  canvas.restore();
}

/// The lamp: an ellipse of [accent] hung at the top centre of the room, whole
/// at its centre and gone at its rim.
void _paintLamp(
  Canvas canvas,
  Rect room,
  Color accent,
  bool dark,
  double strength,
) {
  final alpha =
      (dark
          ? DesignTokensDark.opacityAmbientGlow
          : DesignTokensLight.opacityAmbientGlow) *
      strength;
  final rx = (LampMetrics.widthFraction * (room.width + 160)).clamp(
    LampMetrics.radius,
    LampMetrics.maxWidth,
  );
  const ry = LampMetrics.radius;
  canvas.save();
  canvas.translate(room.center.dx, room.top + LampMetrics.centreTop);
  canvas.scale(rx / ry, 1);
  const circle = Rect.fromLTRB(-ry, -ry, ry, ry);
  canvas.drawRect(
    circle,
    Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: alpha),
          accent.withValues(alpha: 0),
        ],
      ).createShader(circle),
  );
  canvas.restore();
}

void _paintPicture(Canvas canvas, ui.Image image, Rect box, double strength) {
  if (strength <= 0) return;
  final art = _BakedPicture.of(image);
  if (art == null) return;
  // The bake's inner square is the box; its margin is the blur running past
  // the box's edge.
  final inner = (image.width - 2 * art.inset).toDouble();
  final sx = box.width / inner;
  final sy = box.height / inner;
  final dst = Rect.fromLTRB(
    box.left - art.inset * sx,
    box.top - art.inset * sy,
    box.right + art.inset * sx,
    box.bottom + art.inset * sy,
  );
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    dst,
    Paint()
      ..color = Color.fromRGBO(0, 0, 0, RoomLightMetrics.opacity * strength)
      ..filterQuality = FilterQuality.high,
  );
}

/// Where the lamp hangs and how far it reaches (a
/// radial at the top centre, gone by 70% of its reach).
abstract final class LampMetrics {
  /// How far below the room's top the lamp's centre hangs.
  static const double centreTop = 40;

  /// Its vertical reach, and the least horizontal one.
  static const double radius = 230;

  /// Its horizontal reach as a fraction of the room (plus the box's 160 of
  /// overhang), and the most of it.
  static const double widthFraction = 0.42;
  static const double maxWidth = 480;
}

/// A decoded bake and the inset it was baked with.
class _BakedPicture {
  _BakedPicture(this.inset);
  final int inset;

  static final _insets = Expando<_BakedPicture>();

  static _BakedPicture? of(ui.Image image) => _insets[image];
}

/// The pictures already decoded, newest last, so returning to a title (or a
/// slide coming round again) is lit on the first frame.
final _decoded = <(RoomArt, Brightness), Future<ui.Image>>{};
const _decodedKept = 16;

Future<ui.Image> _decode(RoomArt art, Brightness brightness) {
  final key = (art, brightness);
  final kept = _decoded.remove(key);
  if (kept != null) return _decoded[key] = kept;
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    brightness == Brightness.dark ? art.dark : art.day,
    art.size,
    art.size,
    ui.PixelFormat.rgba8888,
    (image) {
      _BakedPicture._insets[image] = _BakedPicture(art.inset);
      done.complete(image);
    },
  );
  _decoded[key] = done.future;
  // Evicted pictures are dropped, not disposed: a room may still be painting
  // one, and the engine frees it with its last reference.
  while (_decoded.length > _decodedKept) {
    _decoded.remove(_decoded.keys.first);
  }
  return done.future;
}

/// The room itself: decodes its picture and brings it up, then paints.
class _Room extends StatefulWidget {
  const _Room({required this.accent, required this.art, required this.child});

  final Color accent;
  final RoomArt? art;
  final Widget child;

  @override
  State<_Room> createState() => _RoomState();
}

class _RoomState extends State<_Room> with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: AppAnimation.light,
    value: 1,
  );
  ui.Image? _picture;
  ui.Image? _leaving;
  (RoomArt, Brightness)? _wanted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _want();
  }

  @override
  void didUpdateWidget(_Room oldWidget) {
    super.didUpdateWidget(oldWidget);
    _want();
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  void _want() {
    final brightness = Theme.of(context).brightness;
    final art = widget.art;
    final wanted = art == null ? null : (art, brightness);
    if (wanted == _wanted) return;
    _wanted = wanted;
    if (wanted == null) {
      _arrive(null);
      return;
    }
    _decode(wanted.$1, wanted.$2).then((image) {
      if (!mounted || _wanted != wanted) return;
      _arrive(image);
    });
  }

  void _arrive(ui.Image? image) {
    if (image == _picture) return;
    final seated = MediaQuery.disableAnimationsOf(context);
    setState(() {
      // A picture still coming up is caught where it is: the new one rises
      // over whatever the room shows now.
      _leaving = seated ? null : (_rise.value >= 0.5 ? _picture : _leaving);
      _picture = image;
    });
    if (seated) {
      _rise.value = 1;
      return;
    }
    _rise.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted && _rise.value == 1 && _leaving != null) {
        setState(() => _leaving = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _rise,
      child: widget.child,
      builder: (context, child) {
        final presence = AppAnimation.standardCurve.transform(_rise.value);
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              // Its own layer: a scroll repaints the page, not the room.
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RoomPainter(
                    scheme: scheme,
                    accent: widget.accent,
                    picture: _picture,
                    leaving: _leaving,
                    presence: presence,
                  ),
                ),
              ),
            ),
            AmbientRoom(
              scheme: scheme,
              accent: widget.accent,
              picture: _picture,
              leaving: _leaving,
              presence: presence,
              child: child!,
            ),
          ],
        );
      },
    );
  }
}

class _RoomPainter extends CustomPainter {
  const _RoomPainter({
    required this.scheme,
    required this.accent,
    required this.picture,
    required this.leaving,
    required this.presence,
  });

  final ColorScheme scheme;
  final Color accent;
  final ui.Image? picture;
  final ui.Image? leaving;
  final double presence;

  @override
  void paint(Canvas canvas, Size size) => paintRoom(
    canvas,
    Offset.zero & size,
    scheme: scheme,
    accent: accent,
    picture: picture,
    leaving: leaving,
    presence: presence,
  );

  @override
  bool shouldRepaint(_RoomPainter old) =>
      old.scheme != scheme ||
      old.accent != accent ||
      old.picture != picture ||
      old.leaving != leaving ||
      old.presence != presence;
}

/// A title's light inside a slab (Coming up, In the queue, Now playing):
/// the picture of the light of the slab's first title, laid over the slab's
/// top half lit, so a card about a title glows with it. Fills its parent; the
/// slab clips it. Comes up as a room's picture does, and is simply there under
/// Reduce Motion.
class SlabLight extends StatefulWidget {
  const SlabLight({super.key, required this.art});

  /// The picture, or null for an unlit slab.
  final RoomArt? art;

  /// How much of the picture the slab shows.
  static const double opacity = 0.5;

  @override
  State<SlabLight> createState() => _SlabLightState();
}

class _SlabLightState extends State<SlabLight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: AppAnimation.light,
  );
  ui.Image? _picture;
  (RoomArt, Brightness)? _wanted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _want();
  }

  @override
  void didUpdateWidget(SlabLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _want();
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  void _want() {
    final art = widget.art;
    final wanted = art == null ? null : (art, Theme.of(context).brightness);
    if (wanted == _wanted) return;
    _wanted = wanted;
    if (wanted == null) {
      if (_picture != null) setState(() => _picture = null);
      return;
    }
    _decode(wanted.$1, wanted.$2).then((image) {
      if (!mounted || _wanted != wanted) return;
      setState(() => _picture = image);
      if (MediaQuery.disableAnimationsOf(context)) {
        _rise.value = 1;
      } else {
        _rise.forward(from: 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final picture = _picture;
    if (picture == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SlabLightPainter(picture: picture, rise: _rise),
        ),
      ),
    );
  }
}

class _SlabLightPainter extends CustomPainter {
  _SlabLightPainter({required this.picture, required this.rise})
    : super(repaint: rise);

  final ui.Image picture;
  final Animation<double> rise;

  /// Where the picture lies over the slab: past its left and top edges, as
  /// tall as a tall slab (`left −40 top −80`, 360 tall).
  static const double _overhang = 40;
  static const double _top = -80;
  static const double _height = 360;

  @override
  void paint(Canvas canvas, Size size) {
    final presence = AppAnimation.standardCurve.transform(rise.value);
    _paintPicture(
      canvas,
      picture,
      Rect.fromLTWH(-_overhang, _top, size.width + 2 * _overhang, _height),
      presence * SlabLight.opacity / RoomLightMetrics.opacity,
    );
  }

  @override
  bool shouldRepaint(_SlabLightPainter old) => old.picture != picture;
}
