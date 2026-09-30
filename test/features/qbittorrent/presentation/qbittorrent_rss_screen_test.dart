import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/qbittorrent/domain/models/rss.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  qbittorrentUrl: 'https://qbit.test',
  qbittorrentUsername: 'admin',
  qbittorrentPassword: 'secret',
);

const _feed = QbittorrentRssFeed(
  path: r'Linux\Ubuntu',
  url: 'https://example.test/ubuntu.xml',
  title: 'Ubuntu releases',
  unreadCount: 3,
  isLoading: false,
  hasError: false,
);

const _rule = QbittorrentRssRule(
  name: 'Linux ISOs',
  enabled: true,
  mustContain: 'ubuntu',
  mustNotContain: '',
  affectedFeeds: [r'Linux\Ubuntu'],
  assignedCategory: 'software',
  lastMatch: '',
);

void main() {
  testWidgets('checks configuration before reading RSS providers', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
          qbittorrentRssFeedsProvider.overrideWith(
            (ref) => throw StateError('must not be read'),
          ),
          qbittorrentRssRulesProvider.overrideWith(
            (ref) => throw StateError('must not be read'),
          ),
        ],
        child: const MaterialApp(home: QbittorrentRssScreen()),
      ),
    );

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
  });

  testWidgets('renders feeds and rules as one sentence per row', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.semantics.byLabel(
        'Ubuntu releases, Available, 3 unread, '
        'https://example.test/ubuntu.xml',
      ),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(
        'Linux ISOs, Enabled, Contains ubuntu, software, 1 feeds',
      ),
      findsOneWidget,
    );
  });

  testWidgets('keeps feed data when the independent rules endpoint fails', (
    tester,
  ) async {
    await _pump(tester, rulesFail: true);

    expect(find.text('Ubuntu releases'), findsOneWidget);
    expect(
      find.text(
        'The request to qBittorrent did not complete, so the RSS rules are '
        'not shown.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('distinguishes a feed fault from an unreachable service', (
    tester,
  ) async {
    await _pump(
      tester,
      feeds: const [
        QbittorrentRssFeed(
          path: 'Broken',
          url: '',
          title: '',
          unreadCount: 0,
          isLoading: false,
          hasError: true,
        ),
      ],
    );

    expect(
      find.semantics.byLabel('Broken, Fault, 0 unread, —'),
      findsOneWidget,
    );
    expect(find.text('Unreachable'), findsNothing);
  });

  testWidgets('draws explicit empty states for both answered endpoints', (
    tester,
  ) async {
    await _pump(tester, feeds: const [], rules: const []);

    expect(find.text('No RSS feeds'), findsOneWidget);
    expect(find.text('No automatic rules'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  List<QbittorrentRssFeed> feeds = const [_feed],
  List<QbittorrentRssRule> rules = const [_rule],
  bool rulesFail = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => _configured),
        qbittorrentRssFeedsProvider.overrideWith((ref) async => feeds),
        qbittorrentRssRulesProvider.overrideWith((ref) async {
          if (rulesFail) throw Exception('rules unavailable');
          return rules;
        }),
      ],
      child: const MaterialApp(home: QbittorrentRssScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
