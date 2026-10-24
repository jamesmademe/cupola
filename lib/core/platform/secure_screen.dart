import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Marks the widget's lifetime as one the OS must not capture.
///
/// On Android the channel sets `FLAG_SECURE`: the screen disappears from the
/// Recents snapshot, screenshots and screen recordings. On iOS and macOS there
/// is no such flag; [AppSnapshotCover] is the app-wide half that covers the
/// switcher image, and this widget is a no-op there.
///
/// The reference count matters because a sensitive sheet can open over a
/// sensitive page: the second screen must not clear the flag the first one set.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  static const _channel = MethodChannel('com.matthwlabs.cupola/secure_screen');
  static int _holders = 0;

  @override
  void initState() {
    super.initState();
    if (_holders++ == 0) _set(true);
  }

  @override
  void dispose() {
    if (--_holders == 0) _set(false);
    super.dispose();
  }

  /// Best effort on purpose: a host without the channel (iOS, macOS, a widget
  /// test) must not make a screen fail to open.
  static Future<void> _set(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } catch (_) {
      // No native side: the snapshot cover is the platform's half.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
