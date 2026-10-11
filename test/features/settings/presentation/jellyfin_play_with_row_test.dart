import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/stream_player_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';
import 'package:cupola/features/stream/data/stream_app_launcher.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Answers for the apps it is given: no device.
class _Apps implements StreamAppLauncher {
  _Apps(this.installed);

  final Set<String> installed;

  @override
  Future<bool> canOpen(Uri url) async => installed.contains(url.scheme);

  @override
  Future<bool> open(Uri url) async => true;
}

/// The Jellyfin connection's page, on a phone or a desktop.
Future<ProviderContainer> _pumpJellyfin(
  WidgetTester tester, {
  required Set<String> installed,
}) async {
  tester.view.physicalSize = const Size(430, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(
    Profiles.p1,
    overrides: [streamAppLauncherProvider.overrideWithValue(_Apps(installed))],
  );
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ServiceSettingsScreen(
          service: ServiceKey.jellyfin,
          instanceId: WorldIds.jellyfin,
          certificateProber: (_, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
      ),
    ),
  );
  await harness.settle(tester);
  return container;
}

void main() {
  testWidgets('on a phone, the Jellyfin page says where a title plays: asked '
      'every time, until a player is chosen', (tester) async {
    final container = await _pumpJellyfin(tester, installed: {'streamyfin'});
    await tester.pumpAndSettle();

    expect(find.text('Play with'), findsOneWidget);
    expect(find.text('Ask every time'), findsOneWidget);
    expect(container.read(streamPlayerChoiceProvider), isNull);

    await tester.tap(find.text('Play with'));
    await tester.pumpAndSettle();

    // The choices: asking every time, and the players installed here.
    expect(find.text('Ask every time'), findsNWidgets(2));
    expect(find.text('Streamyfin'), findsOneWidget);
    expect(find.text('Jellyfin in the browser'), findsOneWidget);
    expect(find.text('Swiftfin'), findsNothing);
    // The browser last, as in the sheet that plays a title.
    expect(
      tester.getTopLeft(find.text('Streamyfin')).dy,
      lessThan(tester.getTopLeft(find.text('Jellyfin in the browser')).dy),
    );

    await tester.tap(find.text('Streamyfin'));
    await tester.pumpAndSettle();

    expect(container.read(streamPlayerChoiceProvider), StreamPlayer.streamyfin);
    expect(find.text('Ask every time'), findsNothing);
    expect(find.text('Streamyfin'), findsOneWidget);
    expect(
      container.read(sharedPreferencesProvider).getString('stream_player'),
      'streamyfin',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'on a desktop the row is not offered: the browser, as before',
    (tester) async {
      await _pumpJellyfin(tester, installed: {'streamyfin'});
      await tester.pumpAndSettle();

      expect(find.text('Play with'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
