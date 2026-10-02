import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:cupola/core/platform/desktop_window.dart';

/// Opens a page in a browser the person trusts, and closes it again where the
/// platform lets an app close what it opened.
///
/// For a sign-in that happens on someone else's page (app.plex.tv): the
/// password is typed there, never in Cupola. **Never an embedded web view**:
/// one would see the password, and Google refuses to sign in inside one.
///
/// Injected ([browserOpenerProvider]) so a test captures the address instead
/// of opening anything.
abstract interface class BrowserOpener {
  /// Opens [url]. False when nothing could open it.
  Future<bool> open(Uri url);

  /// Closes what [open] opened, where the platform allows it (the in-app
  /// Safari view on iOS), and brings the app back in front on the desktop.
  Future<void> close();
}

final browserOpenerProvider = Provider<BrowserOpener>(
  (ref) => const UrlLauncherBrowserOpener(),
);

/// [BrowserOpener] over `url_launcher`, which the app already depends on.
///
/// - iOS: the in-app Safari view, which [close] can dismiss; the app stays in
///   front and keeps polling.
/// - Android: Custom Tabs where supported, else the browser app. Neither can
///   be closed from here: the person comes back with Back.
/// - macOS, Windows, Linux: the default browser; [close] brings the window
///   back in front.
class UrlLauncherBrowserOpener implements BrowserOpener {
  const UrlLauncherBrowserOpener();

  @override
  Future<bool> open(Uri url) async {
    final mode = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => LaunchMode.inAppBrowserView,
      TargetPlatform.android =>
        await supportsLaunchMode(LaunchMode.inAppBrowserView)
            ? LaunchMode.inAppBrowserView
            : LaunchMode.externalApplication,
      _ => LaunchMode.externalApplication,
    };
    return launchUrl(url, mode: mode);
  }

  @override
  Future<void> close() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await closeInAppWebView();
      } else if (DesktopWindow.isSupported) {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (_) {
      // Closing is a courtesy: a browser the platform will not close stays
      // open, and the sign-in has already finished.
    }
  }
}
