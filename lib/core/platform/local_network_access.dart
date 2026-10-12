import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/network/local_network_target.dart';

/// Whether the host OS is standing between Cupola and the user's own network.
///
/// Three platforms gate that traffic behind a permission the user grants once:
/// iOS 14+, macOS 15+ and, for apps targeting API 37, Android 17+. Every one
/// of them blocks the connection *silently*, so a blocked LAN address is
/// indistinguishable from a wrong one at the socket: iOS reports "no route to
/// host", Android times out. That is the bug this enum exists to close. A first
/// connection test would fail while the OS was still showing its own permission
/// alert, the user would read "could not reach the server", fix nothing, tap
/// Allow, and only find out by testing again.
enum LocalNetworkAccess {
  /// Nothing to ask: this platform (or this OS version) does not gate the local
  /// network, or the address was never on it. The overwhelming majority of
  /// answers, and the one that leaves every other code path untouched.
  unrestricted,

  /// The user has allowed it. A failure is the address, the credentials or the
  /// server, not the permission.
  granted,

  /// Allowed *while Cupola was asking*: the user answered the OS alert during
  /// this very probe.
  ///
  /// Held apart from [granted] because it is the one case worth retrying. The
  /// connection that failed a moment ago was dialled while the alert was still
  /// on screen, so its verdict is void: this is the "test again" the user
  /// otherwise has to think of themselves. Retrying on plain [granted] instead
  /// would double the wait on every genuinely wrong LAN address.
  justGranted,

  /// The OS is blocking Cupola. Nothing on the LAN will answer until the user
  /// turns it back on, and no amount of re-typing the address will help.
  denied,

  /// Asked and could not find out: the alert is still on screen unanswered, the
  /// probe timed out, or the host has no answer for us. Claims nothing, so the
  /// caller reports the plain connection failure it already had.
  unknown,
}

/// The shape of [probeLocalNetworkAccess], so a widget or a test can substitute
/// a verdict instead of reaching a real OS. Mirrors how [CertificateProber] is
/// threaded through the same screens.
typedef LocalNetworkProbe =
    Future<LocalNetworkAccess> Function(String rawUrl, {Duration timeout});

/// Asks the host OS whether it is blocking Cupola from reaching [rawUrl].
///
/// Returns [LocalNetworkAccess.unrestricted] without touching the host whenever
/// the question does not apply: a platform with no such gate, or an address
/// that is not on the local network. That ordering is load-bearing: resolving
/// the permission on iOS *shows the system alert* when the user has not answered
/// it yet, and raising a Local Network prompt because a public server timed out
/// would be a worse bug than the one this fixes.
///
/// [timeout] is how long to wait for a verdict. Callers with a human watching
/// should be generous: the wait is the user reading an alert and tapping Allow,
/// while a background refresh should pass something short, because there the
/// only useful answer is one the OS already knows.
Future<LocalNetworkAccess> probeLocalNetworkAccess(
  String rawUrl, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!LocalNetworkPermission.platformMayGate) {
    return LocalNetworkAccess.unrestricted;
  }
  if (!await targetIsOnLocalNetwork(rawUrl)) {
    return LocalNetworkAccess.unrestricted;
  }
  return LocalNetworkPermission.resolve(timeout: timeout);
}

/// The host side of the local-network permission.
///
/// There is no API on any of these platforms that reads the permission without
/// possibly asking for it: Apple's own answer is to start a Bonjour browser and
/// watch for `PolicyDenied`; so this exposes exactly one operation, [resolve],
/// and is honest about the fact that it may put an alert on screen. What makes
/// that safe is *when* Cupola calls it: only after a connection to the LAN has
/// already failed, which on iOS is the very thing that raised the alert. By then
/// resolving does not add a prompt, it waits for the answer to the one already
/// there.
abstract final class LocalNetworkPermission {
  /// The host channel. Public so a test can stand in for the native side.
  static const MethodChannel channel = MethodChannel(
    'com.matthwlabs.cupola/local_network',
  );

  /// Platforms whose OS *may* gate local-network traffic. The OS-version half of
  /// the question is the native side's to answer; it can read the running
  /// version, and answers `unrestricted` below iOS 14, macOS 15 and Android 17.
  static bool get platformMayGate => switch (defaultTargetPlatform) {
    TargetPlatform.iOS ||
    TargetPlatform.macOS ||
    TargetPlatform.android => true,
    _ => false,
  };

  /// Asks the host for a verdict, waiting up to [timeout].
  ///
  /// Holds no state whatsoever, and that is a decision rather than an omission.
  /// Two obvious pieces of state were tried here and both were wrong: caching a
  /// verdict is wrong because the user can revoke this permission in Settings
  /// while the app runs, and sharing one in-flight future between the services
  /// onboarding tests in parallel is wrong because a future abandoned by a
  /// disposed widget tree is never completed; it becomes a shared promise that
  /// can only hang, and every later caller in the process inherits it. The
  /// coalescing that saves is real but belongs to the host, which can tear its
  /// probe down and answer every waiter at once.
  ///
  /// Deliberately impossible to throw: a platform with no handler registered and
  /// a native failure both come back as a verdict that claims nothing. A
  /// permission check that can break a connection test is worse than no
  /// permission check at all.
  static Future<LocalNetworkAccess> resolve({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      // [timeout] crosses the channel so the host can tear its own probe down,
      // and is *also* enforced here. The duplication is deliberate: a channel
      // with nothing listening does not fail, it simply never answers; that is
      // what a test binding with no mock handler does, and a permission check
      // that can hang is a connection test that never finishes. Whatever this
      // returns, it returns.
      final verdict = await channel
          .invokeMethod<String>('resolve', {
            'timeoutMs': timeout.inMilliseconds,
          })
          .timeout(timeout + const Duration(seconds: 2));
      return switch (verdict) {
        'granted' => LocalNetworkAccess.granted,
        'just_granted' => LocalNetworkAccess.justGranted,
        'denied' => LocalNetworkAccess.denied,
        'unrestricted' => LocalNetworkAccess.unrestricted,
        _ => LocalNetworkAccess.unknown,
      };
    } on MissingPluginException {
      // A platform this app builds for but has not wired: desktop Linux and
      // Windows, or a test binding. Neither gates the local network.
      return LocalNetworkAccess.unrestricted;
    } catch (_) {
      return LocalNetworkAccess.unknown;
    }
  }

  /// Opens the OS page carrying the toggle, so the fix is one tap from the
  /// failure that named it. Returns false when the host could not get there.
  static Future<bool> openSettings() async {
    try {
      return await channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Where the user has to go, named the way their own OS names it.
  ///
  /// Worth being platform-specific rather than generic: "allow local network
  /// access" is advice, while "Settings › Privacy & Security › Local Network" is
  /// a route. The button beside this sentence goes there directly, and the words
  /// are what makes the button's destination predictable.
  static String get remedy => switch (defaultTargetPlatform) {
    TargetPlatform.iOS =>
      'Turn on Local Network for Cupola in Settings › Privacy & Security › '
          'Local Network, then test again.',
    TargetPlatform.macOS =>
      'Turn on Cupola under System Settings › Privacy & Security › Local '
          'Network, then test again.',
    TargetPlatform.android =>
      "Allow Cupola to reach your local network in Android's app permissions, "
          'then test again.',
    _ => 'Allow Cupola to reach your local network, then test again.',
  };
}
