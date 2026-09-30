import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_tab_screens.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  sabnzbdUrl: 'https://sab.test',
  sabnzbdApiKey: 'secret',
);

void main() {
  testWidgets('both tabs stop before their providers when not configured', (
    tester,
  ) async {
    var historyReads = 0;
    var configReads = 0;
    var statsReads = 0;
    final overrides = <Override>[
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
      sabnzbdHistoryProvider.overrideWith((ref) async {
        historyReads++;
        return const [];
      }),
      sabnzbdServersProvider.overrideWith((ref) async {
        configReads++;
        return const [];
      }),
      sabnzbdServerStatsProvider.overrideWith((ref) async {
        statsReads++;
        return _stats();
      }),
    ];

    for (final screen in const <Widget>[
      SabnzbdHistoryScreen(),
      SabnzbdServersScreen(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: overrides,
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    }

    expect(historyReads, 0);
    expect(configReads, 0);
    expect(statsReads, 0);
  });

  testWidgets('failed history is one amber fault sentence', (tester) async {
    await _pump(
      tester,
      screen: const SabnzbdHistoryScreen(),
      overrides: [
        sabnzbdHistoryProvider.overrideWith(
          (ref) async => const [
            SabnzbdHistorySlot(
              nzoId: 'broken',
              name: 'Broken release',
              status: 'Failed',
              category: 'movies',
              bytes: 0,
              completed: null,
              failMessage: 'Missing articles',
            ),
          ],
        ),
      ],
    );

    expect(
      find.semantics.byLabel(
        'Broken release, Failed, movies, 0 B, completion time unavailable, Missing articles',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('0 B'), findsOneWidget);
    expect(find.textContaining('· — · Missing articles'), findsOneWidget);

    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded));
    final colorScheme = Theme.of(
      tester.element(find.byType(SabnzbdHistoryScreen)),
    ).colorScheme;
    expect(
      icon.color,
      statusToneColor(
        colorScheme,
        StatusTone.warning,
        surface: colorScheme.surfaceContainer,
      ),
    );
  });

  testWidgets('history filters only the recent window in hand', (tester) async {
    await _pump(
      tester,
      screen: const SabnzbdHistoryScreen(),
      overrides: [
        sabnzbdHistoryProvider.overrideWith(
          (ref) async => [
            const SabnzbdHistorySlot(
              nzoId: 'ok',
              name: 'Finished release',
              status: 'Completed',
              category: 'tv',
              bytes: 1024,
              completed: null,
            ),
            const SabnzbdHistorySlot(
              nzoId: 'bad',
              name: 'Failed release',
              status: 'Failed',
              category: 'tv',
              bytes: 2048,
              completed: null,
            ),
          ],
        ),
      ],
    );

    await tester.tap(find.bySemanticsLabel('Failed'));
    await tester.pump();

    expect(find.text('Failed release'), findsOneWidget);
    expect(find.text('Finished release'), findsNothing);
    expect(find.textContaining('Showing'), findsNothing);
  });

  testWidgets('servers keep configuration when volume stats fail', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const SabnzbdServersScreen(),
      overrides: [
        sabnzbdServersProvider.overrideWith(
          (ref) async => const [
            SabnzbdServerConfig(
              name: 'Primary',
              host: 'news.example.test',
              port: 563,
              connections: 20,
              enabled: true,
              ssl: true,
              optional: false,
              priority: 0,
            ),
          ],
        ),
        sabnzbdServerStatsProvider.overrideWith(
          (ref) => Future.error(Exception('stats unavailable')),
        ),
      ],
    );

    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(
      find.text(
        'The request to SABnzbd did not complete, so the transfer volume is '
        'not shown.',
      ),
      findsOneWidget,
    );
    expect(find.byType(AppErrorState), findsNothing);
    expect(find.text('0 B'), findsNothing);
  });

  testWidgets('reported zero volume remains zero rather than unavailable', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const SabnzbdServersScreen(),
      overrides: [
        sabnzbdServersProvider.overrideWith((ref) async => const []),
        sabnzbdServerStatsProvider.overrideWith((ref) async => _stats()),
      ],
    );

    expect(find.text('0 B'), findsNWidgets(4));
    expect(
      find.textContaining('the transfer volume is not shown'),
      findsNothing,
    );
  });

  testWidgets('both server calls failing produce one page error', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const SabnzbdServersScreen(),
      overrides: [
        sabnzbdServersProvider.overrideWith(
          (ref) => Future.error(Exception('config unavailable')),
        ),
        sabnzbdServerStatsProvider.overrideWith(
          (ref) => Future.error(Exception('stats unavailable')),
        ),
      ],
    );

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

SabnzbdServerStats _stats() =>
    const SabnzbdServerStats(total: 0, month: 0, week: 0, day: 0, servers: []);

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _configured),
        ...overrides,
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}
