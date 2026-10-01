import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../settings_scope.dart';
import 'config_profile.dart';
import 'profile_network.dart';

/// A profile made live: its fake network installed, and the overrides that
/// start the app on its settings and its lens.
///
/// The overrides are **only the startup ones** — settings, secure store,
/// onboarding, the lens map. No service provider is overridden: every Radarr,
/// Seerr, qBittorrent, TrueNAS and Dockge client is the app's own, built by
/// the app's own providers, and reaches [network] through `HttpOverrides`.
/// A test that needs to pin something higher up passes it in `overrides`.
class ProfileHarness {
  ProfileHarness._(this.profile, this.network, this.overrides);

  /// Installs [profile]'s network for the current test and builds its
  /// overrides. The network is uninstalled when the test ends.
  static Future<ProfileHarness> start(
    ConfigProfile profile, {
    List<Override> overrides = const [],
    DateTime? now,
  }) async {
    final network = ProfileNetwork(profile, now: now)..install();
    return ProfileHarness._(profile, network, [
      ...await settingsScopeOverrides(customize: (_) => profile.settings),
      initialActiveInstancesProvider.overrideWithValue(profile.lens),
      ...overrides,
    ]);
  }

  final ConfigProfile profile;
  final ProfileNetwork network;

  /// Ready to hand to a `ProviderScope` or a `ProviderContainer`.
  final List<Override> overrides;

  /// A container over [overrides], disposed when the test ends.
  ///
  /// Keeps the app's own retry policy unless [retry] says otherwise: whether a
  /// failed provider retries is part of what a profile exercises (the "about
  /// 40 s of backoff" rows of the inventory).
  ProviderContainer container({
    Duration? Function(int retryCount, Object error)? retry,
  }) {
    final container = ProviderContainer(overrides: overrides, retry: retry);
    addTearDown(container.dispose);
    return container;
  }

  /// Pumps until no frame is scheduled, letting real isolates answer.
  ///
  /// `pumpAndSettle` only turns fake time, and some parses always run in an
  /// `Isolate.run` (Prowlarr's history page does, whatever its size): its
  /// answer arrives on the real event loop, which fake time never turns, so the
  /// section shimmers until `pumpAndSettle` gives up. This yields to the real
  /// loop once per second of fake time. Throws like `pumpAndSettle` when
  /// [timeout] of fake time passes with frames still scheduled — a screen
  /// that animates for ever is a finding, not something to wait out.
  Future<void> settle(
    WidgetTester tester, {
    Duration timeout = const Duration(minutes: 10),
  }) async {
    const step = Duration(milliseconds: 100);
    var elapsed = Duration.zero;
    var ticks = 0;
    do {
      if (ticks++ % 10 == 0) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await tester.pump(step);
      elapsed += step;
      if (elapsed > timeout) {
        throw FlutterError(
          '${profile.id}: still scheduling frames after $timeout of fake time.',
        );
      }
    } while (tester.binding.hasScheduledFrame);
  }

  /// Unmounts the tree and lets the timers its disposal leaves run out.
  ///
  /// **End every widget test that pumps a profile with Dockge in it with
  /// this.** Disposing a Dockge client disconnects its Socket.IO socket, and
  /// socket_io_client defers the write's drain with `Timer.run` — a zero-length
  /// timer `flutter_test` finds still pending after its own teardown, which
  /// pumps no time. Harmless live; a failed test here.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Pumps [child] under [profile]: the app's dark theme, a `ProviderScope`
/// over the profile's overrides, and its network installed.
///
/// [settle] runs [ProfileHarness.settle]; turn it off for a screen that is
/// expected to keep animating, and pump by hand. End the test with
/// [ProfileHarness.unmount].
Future<ProfileHarness> pumpWithProfile(
  WidgetTester tester,
  ConfigProfile profile, {
  required Widget child,
  List<Override> overrides = const [],
  Size? surfaceSize,
  bool settle = true,
  DateTime? now,
}) async {
  final harness = await ProfileHarness.start(
    profile,
    overrides: overrides,
    now: now,
  );
  // A Seerr session, a Quick Connect code and a plex.tv PIN then expire as
  // the app's own timers see time pass.
  harness.network.followFakeTime(tester.binding);
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  if (settle) await harness.settle(tester);
  return harness;
}
