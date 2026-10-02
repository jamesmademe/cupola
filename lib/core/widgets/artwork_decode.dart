import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The size a piece of network artwork is decoded at, in device pixels: the
/// size it is drawn at, and no more.
///
/// Every poster, backdrop and avatar used to decode at the server's own
/// resolution. An arr hands out its original poster, two thousand pixels by
/// three thousand, and a grid tile 111 points wide kept all of it in memory
/// to draw a twentieth of it: some 24 MB a tile. Decoded at the drawn size the
/// same tile is under 1 MB, and it looks the same, because a `cover` picture
/// is never drawn larger than the box it fills.
///
/// One side is fixed and the other follows the picture's own proportions, so
/// nothing is stretched. Which side depends on the box, because a `cover` fill
/// crops whatever the box does not show and the kept side must still fill it
/// whatever the picture's shape: posters (2 : 3), covers and icons (1 : 1) and
/// stills and backdrops (16 : 9) are the shapes the app draws.
///
///  * a box as narrow as a poster or narrower fixes its **height**: every one
///    of those shapes is at least that wide, so its width covers too;
///  * a box as wide as a still or wider fixes its **width**, for the same
///    reason the other way round;
///  * a box in between fixes a height tall enough for a poster as wide as the
///    box, `max(height, width × 3 / 2)`, which covers every shape from a poster
///    up.
///
/// The ratio is never taken under 2: a 1x display is the exception, and a
/// picture drawn at twice its screen's ratio (a capture at 2x) must not come
/// out softer than it did. The figure is rounded up to a rung of a ladder of
/// steps an eighth to a quarter apart, so a box a point wider is not a new
/// decode, and a window being resized decodes again only at a rung. A picture
/// smaller than the figure is never enlarged ([ResizeImage]'s
/// `allowUpscaling` stays false).
@immutable
class ArtworkCacheSize {
  const ArtworkCacheSize._({this.width, this.height});

  /// No decode size: the box gave none on either side, so the picture is
  /// decoded whole.
  static const ArtworkCacheSize none = ArtworkCacheSize._();

  /// Pass as `memCacheWidth`, or as [ResizeImage]'s `width`.
  final int? width;

  /// Pass as `memCacheHeight`, or as [ResizeImage]'s `height`.
  final int? height;

  /// [provider] decoded at this size; [provider] itself for [none].
  ImageProvider<Object> resize(ImageProvider<Object> provider) =>
      ResizeImage.resizeIfNeeded(width, height, provider);

  @override
  bool operator ==(Object other) =>
      other is ArtworkCacheSize &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'ArtworkCacheSize(width: $width, height: $height)';
}

/// The narrowest shape the app draws artwork in, a poster.
const double _posterAspect = 2 / 3;

/// The widest shape the app draws artwork in, a still or a backdrop.
const double _stillAspect = 16 / 9;

/// The lowest pixel ratio a picture is decoded for; see [ArtworkCacheSize].
const double _ratioFloor = 2;

/// The decode size for artwork drawn `cover` into [box] at
/// [devicePixelRatio]; see [ArtworkCacheSize]. An infinite or zero side is a
/// side the box does not fix: the picture keeps its own proportions there,
/// so only the other side is bounded.
ArtworkCacheSize artworkCacheSize(Size box, double devicePixelRatio) {
  bool fixes(double side) => side.isFinite && side > 0;
  final hasWidth = fixes(box.width);
  final hasHeight = fixes(box.height);
  final ratio = math.max(devicePixelRatio, _ratioFloor);
  int px(double logical) => _rung(logical * ratio);

  if (!hasWidth && !hasHeight) return ArtworkCacheSize.none;
  if (!hasHeight) return ArtworkCacheSize._(width: px(box.width));
  if (!hasWidth) return ArtworkCacheSize._(height: px(box.height));

  final aspect = box.width / box.height;
  if (aspect <= _posterAspect) {
    return ArtworkCacheSize._(height: px(box.height));
  }
  if (aspect >= _stillAspect) {
    return ArtworkCacheSize._(width: px(box.width));
  }
  return ArtworkCacheSize._(
    height: px(math.max(box.height, box.width / _posterAspect)),
  );
}

/// [pixels] rounded up to the ladder: within each power of two, quarters of
/// it (… 256, 320, 384, 448, 512, 640 …), from 64 up.
int _rung(double pixels) {
  if (!pixels.isFinite || pixels <= 64) return 64;
  final octave = 1 << (math.log(pixels) / math.ln2).floor();
  final step = octave ~/ 4;
  return (pixels / step).ceil() * step;
}

/// Builds artwork with the decode size of the box it is laid out in.
///
/// For a picture that fills whatever its parent gives it (a grid tile, a
/// poster, a backdrop): the box is the constraints it receives. [box] fixes it
/// instead, for a slot whose layout does not say what the picture was decoded
/// for — a hero shuttle, whose size animates while its picture must stay the
/// one already decoded.
class ArtworkDecodeBox extends StatelessWidget {
  const ArtworkDecodeBox({super.key, required this.builder, this.box});

  /// A fixed box to decode for, in logical pixels.
  final Size? box;

  final Widget Function(BuildContext context, ArtworkCacheSize decode) builder;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final fixed = box;
    if (fixed != null) {
      return builder(context, artworkCacheSize(fixed, ratio));
    }
    return LayoutBuilder(
      builder: (context, constraints) => builder(
        context,
        artworkCacheSize(
          Size(
            constraints.hasBoundedWidth
                ? constraints.maxWidth
                : double.infinity,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : double.infinity,
          ),
          ratio,
        ),
      ),
    );
  }
}
