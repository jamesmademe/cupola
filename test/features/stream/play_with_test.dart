import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/stream_player_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/data/stream_app_launcher.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';
import 'package:cupola/features/stream/presentation/play_with.dart';

/// Answers for the apps it is given, and records what was opened: no device,
/// no launch.
class _FakeLauncher implements StreamAppLauncher {
  _FakeLauncher({this.installed = const {}, this.opens = true});

  /// The schemes the platform says an app claims.
  final Set<String> installed;

  /// Whether a launch succeeds.
  final bool opens;

  final opened = <Uri>[];

  @override
  Future<bool> canOpen(Uri url) async => installed.contains(url.scheme);

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return opens;
  }
}

/// A remembered choice, fixed for a test.
class _Remembered extends StreamPlayerChoiceNotifier {
  _Remembered(this.player);

  final StreamPlayer? player;

  @override
  StreamPlayer? build() => player;
}

final _webUrl = Uri.parse(
  'https://jellyfin.example.com/web/index.html#!/details?id=item1',
);

ServiceInstance _jellyfin() => const ServiceInstance(
  id: 'jf-1',
  service: ServiceKey.jellyfin,
  url: 'https://jellyfin.example.com',
  credential: 'k',
  viewerId: 'usr1',
);

/// A button that plays [server]'s item, through [playWith], as the three call
/// sites do.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeLauncher launcher,
  ServiceInstance? server,
  StreamPlayer? remembered,
  Uri? webUrl,
}) async {
  final container = ProviderContainer(
    overrides: [
      streamAppLauncherProvider.overrideWithValue(launcher),
      jellyfinServerIdProvider.overrideWith((ref, instanceId) async => 'srv1'),
      streamPlayerChoiceProvider.overrideWith(() => _Remembered(remembered)),
    ],
  );
  addTearDown(container.dispose);
  final target = server ?? _jellyfin();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: FilledButton(
                onPressed: () => playWith(
                  context,
                  ref,
                  server: target,
                  itemId: 'item1',
                  title: 'Tears of Steel',
                  webUrl: webUrl ?? _webUrl,
                ),
                child: const Text('Play'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

Future<void> _play(WidgetTester tester) async {
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a remembered app that is still installed opens at once, with no '
      'sheet', (tester) async {
    final launcher = _FakeLauncher(installed: {'swiftfin', 'streamyfin'});
    await _pump(
      tester,
      launcher: launcher,
      remembered: StreamPlayer.swiftfin,
      webUrl: _webUrl,
    );

    await _play(tester);

    expect(find.text('Play with'), findsNothing);
    expect(
      launcher.opened.single.toString(),
      'swiftfin://srv1/usr1/item/item1',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a remembered app uninstalled since is forgotten, and the sheet '
      'asks again', (tester) async {
    final launcher = _FakeLauncher(installed: {'streamyfin'});
    final container = await _pump(
      tester,
      launcher: launcher,
      remembered: StreamPlayer.swiftfin,
    );

    await _play(tester);

    expect(container.read(streamPlayerChoiceProvider), isNull);
    expect(find.text('Play with'), findsOneWidget);
    expect(find.text('Streamyfin'), findsOneWidget);
    expect(launcher.opened, isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('with no app installed, the browser opens with no sheet, as it '
      'always did', (tester) async {
    final launcher = _FakeLauncher();
    await _pump(tester, launcher: launcher);

    await _play(tester);

    expect(find.text('Play with'), findsNothing);
    expect(launcher.opened.single, _webUrl);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('with two players, the sheet lists them, the browser last, and '
      'a tap opens the one tapped', (tester) async {
    final launcher = _FakeLauncher(installed: {'swiftfin'});
    await _pump(tester, launcher: launcher);

    await _play(tester);

    expect(find.text('Play with'), findsOneWidget);
    expect(find.text('Tears of Steel'), findsOneWidget);
    expect(find.text('Opens its page'), findsOneWidget);
    expect(find.text('In your browser'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Swiftfin')).dy,
      lessThan(tester.getTopLeft(find.text('Jellyfin in the browser')).dy),
    );

    await tester.tap(find.text('Swiftfin'));
    await tester.pumpAndSettle();

    expect(
      launcher.opened.single.toString(),
      'swiftfin://srv1/usr1/item/item1',
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    'ticking the box remembers the choice made in the sheet',
    (tester) async {
      final launcher = _FakeLauncher(installed: {'swiftfin'});
      final container = await _pump(tester, launcher: launcher);

      await _play(tester);
      await tester.tap(find.text('Remember my choice'));
      await tester.pump();
      await tester.tap(find.text('Swiftfin'));
      await tester.pumpAndSettle();

      expect(container.read(streamPlayerChoiceProvider), StreamPlayer.swiftfin);
      expect(launcher.opened.single.scheme, 'swiftfin');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'without the box, the choice is not remembered',
    (tester) async {
      final launcher = _FakeLauncher(installed: {'swiftfin'});
      final container = await _pump(tester, launcher: launcher);

      await _play(tester);
      await tester.tap(find.text('Swiftfin'));
      await tester.pumpAndSettle();

      expect(container.read(streamPlayerChoiceProvider), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'a launch that fails says which player could not open',
    (tester) async {
      final launcher = _FakeLauncher(installed: {'swiftfin'}, opens: false);
      await _pump(
        tester,
        launcher: launcher,
        remembered: StreamPlayer.swiftfin,
      );

      await _play(tester);

      expect(find.text('Could not open Swiftfin'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Plex keeps its browser link, with no sheet',
    (tester) async {
      final launcher = _FakeLauncher(installed: {'swiftfin'});
      await _pump(
        tester,
        launcher: launcher,
        server: const ServiceInstance(
          id: 'plex-1',
          service: ServiceKey.plex,
          url: 'https://plex.example.com',
          credential: 'k',
        ),
      );

      await _play(tester);

      expect(find.text('Play with'), findsNothing);
      expect(launcher.opened.single, _webUrl);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'on a desktop there is no sheet: the browser, as today',
    (tester) async {
      final launcher = _FakeLauncher(installed: {'swiftfin'});
      await _pump(tester, launcher: launcher);

      await _play(tester);

      expect(find.text('Play with'), findsNothing);
      expect(launcher.opened.single, _webUrl);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Swiftfin is not offered without the server id it needs',
    (tester) async {
      final launcher = _FakeLauncher(installed: {'swiftfin', 'streamyfin'});
      final container = ProviderContainer(
        overrides: [
          streamAppLauncherProvider.overrideWithValue(launcher),
          jellyfinServerIdProvider.overrideWith(
            (ref, instanceId) async => null,
          ),
          streamPlayerChoiceProvider.overrideWith(() => _Remembered(null)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: FilledButton(
                    onPressed: () => playWith(
                      context,
                      ref,
                      server: _jellyfin(),
                      itemId: 'item1',
                      title: 'Tears of Steel',
                      webUrl: _webUrl,
                    ),
                    child: const Text('Play'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await _play(tester);

      expect(find.text('Swiftfin'), findsNothing);
      expect(find.text('Streamyfin'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
