import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Asks the platform whether a stream app is installed, and opens a link in
/// the app that claims it.
///
/// A port over `url_launcher`, injected ([streamAppLauncherProvider]) so a test
/// answers for the apps it chooses without opening anything.
abstract interface class StreamAppLauncher {
  /// Whether the platform can open [url]: an app claims its scheme.
  Future<bool> canOpen(Uri url);

  /// Opens [url]. False when nothing took it.
  Future<bool> open(Uri url);
}

final streamAppLauncherProvider = Provider<StreamAppLauncher>(
  (ref) => const UrlStreamAppLauncher(),
);

/// [StreamAppLauncher] over `url_launcher`: the app itself, never a browser.
class UrlStreamAppLauncher implements StreamAppLauncher {
  const UrlStreamAppLauncher();

  @override
  Future<bool> canOpen(Uri url) async {
    try {
      return await canLaunchUrl(url);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
