import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';

/// The camera, pointed at the other device's code: the first code that is a
/// pairing link closes the screen and hands that link back to whoever opened
/// it. A code that is something else says so and the camera keeps looking.
///
/// Opened by *Scan code* in Copy from another device, on a phone only. The
/// link never leaves this screen as text: it is parsed here, and only the
/// [PairLink] is returned.
///
/// **A dark room on purpose.** The preview is a photograph that fills the
/// screen, so the chrome over it is white on a black scrim in both themes, as
/// a camera's is.
class PairScanScreen extends StatefulWidget {
  const PairScanScreen({super.key});

  /// Opens the scanner over [context] and returns the link it read, or `null`
  /// when the person went back.
  static Future<PairLink?> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push<PairLink>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const PairScanScreen(),
        ),
      );

  @override
  State<PairScanScreen> createState() => _PairScanScreenState();
}

class _PairScanScreenState extends State<PairScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  /// Whether a code was read that is not a pairing link.
  bool _notOurs = false;

  /// Set once a link is read, so a second frame of the same code does not
  /// pop twice.
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      final link = PairLink.tryParse(raw);
      if (link != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(link);
        return;
      }
    }
    if (!_notOurs) setState(() => _notOurs = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final side = (size.shortestSide * 0.7).clamp(200.0, 320.0);
    final window = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: side,
      height: side,
    );
    final caption = theme.textTheme.bodyMedium!.copyWith(color: Colors.white);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            scanWindow: window,
            errorBuilder: (context, error) => _CameraUnavailable(error),
          ),
          // The window and its caption only while the camera runs: a camera
          // that cannot start says so alone, under the close button.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => state.error != null
                ? const SizedBox.shrink()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        child: CustomPaint(painter: _WindowScrim(window)),
                      ),
                      _caption(caption),
                    ],
                  ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.xs,
                    top: AppSpacing.xs,
                  ),
                  child: CloseButton(
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(TextStyle style) => SafeArea(
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
        child: Semantics(
          liveRegion: true,
          child: Text(
            _notOurs
                ? 'This code is not from Cupola. On the other device, open '
                      'Settings › Set up another device.'
                : 'Point the camera at the code on the other device.',
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      ),
    ),
  );
}

/// What the screen says when the camera cannot start: refused, or missing.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable(this.error);

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refused = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                refused
                    ? 'Allow the camera for Cupola in Settings, or go back '
                          'and paste the link from the other device.'
                    : 'The camera could not start. Go back and paste the '
                          'link from the other device.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dims everything but the window the scanner reads, and draws its corners.
class _WindowScrim extends CustomPainter {
  const _WindowScrim(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(
      window,
      const Radius.circular(AppRadius.lg),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(hole),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      hole,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WindowScrim old) => old.window != window;
}
