import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import 'package:cupola/core/app_radius.dart';

/// A QR code of [data], drawn on a tile a camera can read.
///
/// **Black on white in both rooms, on purpose.** A scanner looks for dark
/// modules on a light ground, so the code never takes the room's ink or
/// ground: in the dark room it is a white tile, and that is correct. It is the
/// one place in the app where a raw `Colors.black` and `Colors.white` are the
/// right paint, and the only reason they are written here.
///
/// The tile is [size] on a side, its corners [AppRadius.md], and holds the code
/// with the four-module quiet zone the QR standard asks for. The module is
/// snapped down to a whole **device** pixel (so no module straddles a pixel and
/// blurs into its neighbour, and a dense code still uses the tile it is on:
/// snapping to a logical pixel would waste up to a third of it on a phone's
/// 3x screen), the code is centred in the tile, and all the dark modules are
/// one path, so no hairline shows between two that touch.
///
/// Error correction is level M. The code is built once per [data], not per
/// frame.
class QrCodeView extends StatefulWidget {
  const QrCodeView({
    super.key,
    required this.data,
    required this.size,
    required this.semanticLabel,
  });

  /// What the code says: the text a scanner reads out of it.
  final String data;

  /// The tile's side, in logical pixels.
  final double size;

  /// What the image is, in words, for a screen reader: the code itself is
  /// unreadable to one.
  final String semanticLabel;

  /// The quiet zone the standard asks for, in modules, on each side.
  static const quietZoneModules = 4;

  @override
  State<QrCodeView> createState() => _QrCodeViewState();
}

class _QrCodeViewState extends State<QrCodeView> {
  late QrImage _image = _encode(widget.data);

  static QrImage _encode(String data) => QrImage(
    QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
  );

  @override
  void didUpdateWidget(QrCodeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _image = _encode(widget.data);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _QrPainter(
            _image,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image, {required this.devicePixelRatio});

  final QrImage image;
  final double devicePixelRatio;

  // The code's own colours, not the room's: a scanner needs dark on light in
  // either theme (see [QrCodeView]).
  static const _tile = Colors.white;
  static const _module = Colors.black;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadius.md),
    );
    canvas.drawRRect(tile, Paint()..color = _tile);

    // The code is laid out in device pixels, so every module edge is a whole
    // one: whole pixels per module, the code on a whole pixel of the tile.
    final scale = devicePixelRatio;
    final span = image.moduleCount + 2 * QrCodeView.quietZoneModules;
    final sideDevice = size.shortestSide * scale;
    // A tile too small for a whole pixel per module at this code's density
    // falls back to the fraction that fits, rather than drawing past its edge.
    final whole = (sideDevice / span).floorToDouble();
    final module = whole >= 1 ? whole : sideDevice / span;
    final origin = Offset(
      ((size.width * scale - module * image.moduleCount) / 2).floorToDouble(),
      ((size.height * scale - module * image.moduleCount) / 2).floorToDouble(),
    );

    final dark = Path();
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        dark.addRect(
          Rect.fromLTWH(
            origin.dx + col * module,
            origin.dy + row * module,
            module,
            module,
          ),
        );
      }
    }
    canvas
      ..save()
      ..scale(1 / scale)
      ..drawPath(dark, Paint()..color = _module)
      ..restore();
  }

  /// The code is built once per payload and a new payload builds a new
  /// image, so an unchanged image is an unchanged picture; a screen of
  /// another density snaps it differently. A change of size lays the box out
  /// again, which paints it.
  @override
  bool shouldRepaint(_QrPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
