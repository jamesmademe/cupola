import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';

/// Where the room's picture of its light sits, and how it is laid in
/// (brand book, *The title light*).
///
/// The picture is the artwork itself, blurred past recognition, laid over the
/// top of the room in a box wider than the phone and faded into the ground by
/// a scrim: the colours of the poster spill onto the wall the way a
/// television's light does. Lengths are logical pixels from the room's top
/// left; they are the phone's, and a wider room keeps them, so a tablet is lit
/// from its top left corner rather than across its whole width.
abstract final class RoomLightMetrics {
  /// The box the artwork covers, centred on a phone (`left` −120 at 390pt).
  static const double boxWidth = 630;

  /// How far the box widens with a wide room: 0.64 of its width.
  static const double boxWidthFraction = 0.64;
  static const double boxHeight = 640;
  static const double boxTop = -60;

  /// The box's left edge in a room wider than the box.
  static const double boxInsetWide = -60;

  /// The blur, as a fraction of the box: 70 over 630.
  static const double blurFraction = 70 / 630;

  /// How opaque the picture is laid in.
  static const double opacity = 0.72;

  /// The scrim over it, in the ground: the alpha at each stop, and where the
  /// stops are. Whole by 640, where the box ends.
  static const List<double> scrimStops = [0, 300, 540, 640];
  static const List<double> darkScrimAlphas = [0.12, 0.50, 0.94, 1];
  static const List<double> dayScrimAlphas = [0.12, 0.60, 0.94, 1];

  /// How saturated the picture is laid in: twice in the dark room, a little
  /// more than the artwork on paper.
  static const double darkSaturation = 2.0;
  static const double daySaturation = 1.4;

  /// The light behind text, at its strongest (the top of the room, under the
  /// lightest scrim): at most this relative luminance in the dark room, so
  /// secondary text on it stays legible, and at least [dayFloor] on paper, so
  /// a dark poster tints the page instead of darkening it.
  ///
  /// Half the brightest room measured on a phone (a pink and yellow poster,
  /// about 0.06 at the top): a bright poster lit its room five times more
  /// than a dark one lit its own. A dark poster stays under it, unchanged.
  static const double darkCeiling = 0.03;
  static const double dayFloor = 0.72;

  /// The box the picture covers in a room [width] wide.
  static ({double left, double top, double width, double height}) box(
    double width,
  ) {
    final boxW = math.max(boxWidth, width * boxWidthFraction);
    return (
      left: boxW > width ? -(boxW - width) / 2 : boxInsetWide,
      top: boxTop,
      width: boxW,
      height: boxHeight,
    );
  }
}

/// A title's light as a picture: the artwork cropped to the room's box,
/// blurred, saturated and kept within the luminance the room's text can sit
/// on, once for each room.
///
/// Premultiplied RGBA, [size] a side, square, the box's edge [inset] in from
/// each side: the blur runs past the box and fades out, as it does on a
/// picture with nothing around it. Small (about 70 texels a side) because a
/// blurred picture holds no detail; the room scales it up, which costs what a
/// gradient costs, so nothing blurs while the page scrolls (the
/// No-Blur-Under-Scroll Rule).
@immutable
class RoomArt {
  const RoomArt({
    required this.source,
    required this.size,
    required this.inset,
    required this.dark,
    required this.day,
    this.chroma = 0,
  });

  /// The artwork it was read from: two bakes of one picture are one light.
  final String source;
  final int size;
  final int inset;
  final Uint8List dark;
  final Uint8List day;

  /// How coloured the picture lights the dark room, 0 to 1: the mean chroma
  /// (the brightest channel less the dimmest) of the dark bake over its box.
  /// Read off the bake rather than the artwork, so a poster with a small
  /// bright patch on black weighs what its room will show. Where a room may
  /// take its light from one of several titles, it takes the most coloured.
  final double chroma;

  @override
  bool operator ==(Object other) =>
      other is RoomArt &&
      other.source == source &&
      other.size == size &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(source, size, inset);
}

/// A picture decoded small: premultiplied RGBA, one byte a channel, row by
/// row.
typedef ArtworkPixels = ({Uint8List rgba, int width, int height});

/// What [bakeRoomArt] reads: where the picture came from, and its pixels.
typedef RoomArtSource = ({String source, ArtworkPixels pixels});

/// The room's picture of [input], or null for a picture too small to light
/// anything. Pure and isolate-safe: the title light's provider runs it in
/// the same `compute` as the light's colours.
RoomArt? bakeRoomArt(RoomArtSource input) {
  final src = input.pixels;
  final side = math.min(src.width, src.height);
  if (side < 4) return null;
  // Cover, as the box does: the middle square.
  final x0 = (src.width - side) ~/ 2;
  final y0 = (src.height - side) ~/ 2;
  final sigma = side * RoomLightMetrics.blurFraction;
  final inset = (sigma * 3).ceil();
  final n = side + 2 * inset;

  // Premultiplied planes, nothing around the picture.
  final planes = List.generate(4, (_) => Float32List(n * n));
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final from = ((y0 + y) * src.width + x0 + x) * 4;
      final to = (y + inset) * n + x + inset;
      for (var c = 0; c < 4; c++) {
        planes[c][to] = src.rgba[from + c] / 255;
      }
    }
  }

  final kernel = _gaussian(sigma, inset);
  for (final plane in planes) {
    _blur(plane, n, kernel);
  }

  final dark = Uint8List(n * n * 4);
  final day = Uint8List(n * n * 4);
  final darkGround = _rgb(DesignTokensDark.colorRoomGround.toARGB32());
  final dayGround = _rgb(DesignTokensLight.colorRoomGround.toARGB32());
  var chroma = 0.0;
  final reach =
      RoomLightMetrics.opacity * (1 - RoomLightMetrics.darkScrimAlphas.first);
  final dayReach =
      RoomLightMetrics.opacity * (1 - RoomLightMetrics.dayScrimAlphas.first);
  for (var i = 0; i < n * n; i++) {
    final a = planes[3][i].clamp(0.0, 1.0);
    if (a < 1 / 255) continue;
    final rgb = [planes[0][i] / a, planes[1][i] / a, planes[2][i] / a];
    final lit = _ceiling(
      _saturate(rgb, RoomLightMetrics.darkSaturation),
      darkGround,
      reach * a,
      RoomLightMetrics.darkCeiling,
    );
    _write(dark, i, lit, a);
    final (x, y) = (i % n - inset, i ~/ n - inset);
    if (x >= 0 && x < side && y >= 0 && y < side) {
      chroma +=
          (math.max(lit[0], math.max(lit[1], lit[2])) -
              math.min(lit[0], math.min(lit[1], lit[2]))) *
          a;
    }
    _write(
      day,
      i,
      _floor(
        _saturate(rgb, RoomLightMetrics.daySaturation),
        dayGround,
        dayReach * a,
        RoomLightMetrics.dayFloor,
      ),
      a,
    );
  }
  return RoomArt(
    source: input.source,
    size: n,
    inset: inset,
    dark: dark,
    day: day,
    chroma: chroma / (side * side),
  );
}

List<double> _rgb(int argb) => [
  (argb >> 16 & 0xFF) / 255,
  (argb >> 8 & 0xFF) / 255,
  (argb & 0xFF) / 255,
];

Float32List _gaussian(double sigma, int radius) {
  final kernel = Float32List(radius * 2 + 1);
  var sum = 0.0;
  for (var i = -radius; i <= radius; i++) {
    final w = math.exp(-(i * i) / (2 * sigma * sigma));
    kernel[i + radius] = w;
    sum += w;
  }
  for (var i = 0; i < kernel.length; i++) {
    kernel[i] /= sum;
  }
  return kernel;
}

/// A separable blur of [plane], [n] a side, nothing beyond its edges.
void _blur(Float32List plane, int n, Float32List kernel) {
  final radius = kernel.length ~/ 2;
  final line = Float32List(n);
  for (final horizontal in [true, false]) {
    for (var row = 0; row < n; row++) {
      for (var i = 0; i < n; i++) {
        var sum = 0.0;
        for (var k = -radius; k <= radius; k++) {
          final j = i + k;
          if (j < 0 || j >= n) continue;
          sum +=
              kernel[k + radius] *
              plane[horizontal ? row * n + j : j * n + row];
        }
        line[i] = sum;
      }
      for (var i = 0; i < n; i++) {
        plane[horizontal ? row * n + i : i * n + row] = line[i];
      }
    }
  }
}

/// CSS `saturate()`, clamped to the gamut.
List<double> _saturate(List<double> c, double s) {
  final (r, g, b) = (c[0], c[1], c[2]);
  return [
    ((0.213 + 0.787 * s) * r +
            (0.715 - 0.715 * s) * g +
            (0.072 - 0.072 * s) * b)
        .clamp(0.0, 1.0),
    ((0.213 - 0.213 * s) * r +
            (0.715 + 0.285 * s) * g +
            (0.072 - 0.072 * s) * b)
        .clamp(0.0, 1.0),
    ((0.213 - 0.213 * s) * r +
            (0.715 - 0.715 * s) * g +
            (0.072 + 0.928 * s) * b)
        .clamp(0.0, 1.0),
  ];
}

double _linear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// The relative luminance of [c] laid over [ground] at [reach].
double _over(List<double> c, List<double> ground, double reach) {
  double at(int i) => _linear(ground[i] * (1 - reach) + c[i] * reach);
  return 0.2126 * at(0) + 0.7152 * at(1) + 0.0722 * at(2);
}

/// [c] dimmed until, laid over [ground] at [reach], it is no brighter than
/// [ceiling].
List<double> _ceiling(
  List<double> c,
  List<double> ground,
  double reach,
  double ceiling,
) {
  if (_over(c, ground, reach) <= ceiling) return c;
  var (lo, hi) = (0.0, 1.0);
  for (var i = 0; i < 14; i++) {
    final t = (lo + hi) / 2;
    if (_over([c[0] * t, c[1] * t, c[2] * t], ground, reach) > ceiling) {
      hi = t;
    } else {
      lo = t;
    }
  }
  return [c[0] * lo, c[1] * lo, c[2] * lo];
}

/// [c] lifted toward white until, laid over [ground] at [reach], it is no
/// darker than [floor].
List<double> _floor(
  List<double> c,
  List<double> ground,
  double reach,
  double floor,
) {
  if (_over(c, ground, reach) >= floor) return c;
  List<double> lift(double t) => [
    c[0] + (1 - c[0]) * t,
    c[1] + (1 - c[1]) * t,
    c[2] + (1 - c[2]) * t,
  ];
  var (lo, hi) = (0.0, 1.0);
  for (var i = 0; i < 14; i++) {
    final t = (lo + hi) / 2;
    if (_over(lift(t), ground, reach) < floor) {
      lo = t;
    } else {
      hi = t;
    }
  }
  return lift(hi);
}

void _write(Uint8List out, int i, List<double> c, double a) {
  out[i * 4] = (c[0] * a * 255).round();
  out[i * 4 + 1] = (c[1] * a * 255).round();
  out[i * 4 + 2] = (c[2] * a * 255).round();
  out[i * 4 + 3] = (a * 255).round();
}
