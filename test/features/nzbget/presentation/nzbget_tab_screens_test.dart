import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_tab_screens.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  nzbgetUrl: 'https://nzbget.test',
  nzbgetUsername: 'nzbget',
  nzbgetPassword: 'secret',
);

void main() {
  testWidgets('all tab screens stop before providers when not configured', (
    tester,
  ) async {
    for (final screen in const <Widget>[
      NzbgetHistoryScreen(),
      NzbgetFeedsScreen(),
      NzbgetMessagesScreen(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
          child: MaterialApp(home: screen),
        ),
      );
      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    }
  });

  testWidgets('history preserves a failed download as an amber fault', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NzbgetHistoryScreen(),
      overrides: [
        nzbgetHistoryProvider.overrideWith(
          (ref) async => const [
            NzbgetHistoryItem(
              id: 7,
              name: 'Broken release',
              status: 'FAILURE/UNPACK',
              category: 'movies',
            ),
          ],
        ),
      ],
    );

    expect(
      find.semantics.byLabel('Broken release, FAILURE/UNPACK, movies, —'),
      findsOneWidget,
    );
  });

  testWidgets('feeds render configured records without inventing feed items', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NzbgetFeedsScreen(),
      overrides: [
        nzbgetFeedsProvider.overrideWith(
          (ref) async => const [
            NzbgetFeed(
              index: 1,
              name: 'Linux',
              url: 'https://example.test/rss',
              intervalMinutes: 15,
              category: '',
              priority: 0,
              backlog: false,
              pauseNzb: true,
            ),
          ],
        ),
      ],
    );

    expect(
      find.semantics.byLabel(
        'Linux, Every 15\u00A0min, No category, added stopped',
      ),
      findsOneWidget,
    );
  });

  testWidgets('messages expose faults and preserve unavailable timestamps', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const NzbgetMessagesScreen(),
      overrides: [
        nzbgetMessagesProvider.overrideWith(
          (ref) async => const [
            NzbgetMessage(
              id: 9,
              kind: 'WARNING',
              time: null,
              text: 'Article missing',
            ),
          ],
        ),
      ],
    );

    expect(
      find.semantics.byLabel('WARNING, Article missing, —'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a cold endpoint failure renders Retry instead of an empty list',
    (tester) async {
      await _pump(
        tester,
        screen: const NzbgetMessagesScreen(),
        overrides: [
          nzbgetMessagesProvider.overrideWith(
            (ref) => Future.error(Exception('offline')),
          ),
        ],
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );
}

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
