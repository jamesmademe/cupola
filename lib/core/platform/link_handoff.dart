import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Tells the Mac runner the router is listening, so the `cupola://` links it
/// has been holding are handed over.
///
/// The macOS embedder does not route a link by itself: the runner pushes it on
/// `flutter/navigation`, and a push sent before the router has subscribed is
/// dropped without a word. A closed Cupola opened by a link receives it while
/// the start is still reading the Keychain, so the runner holds every link
/// until this says so (`LinkHandoffChannel` in
/// `macos/Runner/MainFlutterWindow.swift`).
abstract final class LinkHandoff {
  static const channel = MethodChannel('com.matthwlabs.cupola/links');

  /// Called right after `runApp` of the app that carries the router. The
  /// signal goes once that app's first frame is drawn: the router subscribes
  /// to route information while it is built, so by then a push reaches it.
  static void routerReadyWhenDrawn() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await channel.invokeMethod<void>('routerReady');
      } on MissingPluginException {
        // A runner without the channel holds no links: nothing to hand over.
      }
    });
  }
}
