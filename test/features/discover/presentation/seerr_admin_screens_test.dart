import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('issues and users render real data and issue action', (
    tester,
  ) async {
    final service = FakeSeerrService()
      ..issues = [
        SeerrIssue(
          id: 7,
          issueType: 2,
          // Overseerr's own spelling: 1 open, 2 resolved.
          status: 1,
          media: const SeerrIssueMedia(title: 'Dune: Part Two'),
          createdBy: const SeerrUser(id: 1, username: 'Matt'),
        ),
      ]
      ..users = const [
        SeerrUser(id: 1, email: 'matt@example.com', requestCount: 3),
      ];

    await _pump(
      tester,
      service: service,
      screen: const SeerrIssuesScreen(topPadding: 0),
    );
    expect(find.text('Dune: Part Two'), findsOneWidget);
    expect(find.text('Audio\u00A0· Matt'), findsOneWidget);
    // Asks first, naming the issue and who reported it; Cancel sends nothing.
    await tester.tap(find.byTooltip('Resolve issue'));
    await tester.pumpAndSettle();
    expect(find.text('Resolve this issue?'), findsOneWidget);
    expect(
      find.textContaining('Dune: Part Two\u00A0· Audio, reported by Matt'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.resolveIssueCalled, isFalse);

    await tester.tap(find.byTooltip('Resolve issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Resolve issue'));
    await tester.pumpAndSettle();
    expect(service.resolveIssueCalled, isTrue);

    await _pump(
      tester,
      service: service,
      screen: const SeerrUsersScreen(topPadding: 0),
    );
    // The email is both the compact identity title and the secondary contact
    // line when Seerr has no separate username.
    expect(find.text('matt@example.com'), findsNWidgets(2));
    expect(find.text('3 requests'), findsOneWidget);
  });

  testWidgets('does not read admin providers before Seerr is configured', (
    tester,
  ) async {
    var issuesRead = false;
    var usersRead = false;
    final overrides = [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
      seerrIssuesProvider(SeerrIssueFilter.open).overrideWith((ref) async {
        issuesRead = true;
        return const SeerrAdminResult<SeerrIssue>(items: [], total: 0);
      }),
      seerrUsersProvider.overrideWith((ref) async {
        usersRead = true;
        return const SeerrAdminResult<SeerrUser>(items: [], total: 0);
      }),
      seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
    ];

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const SeerrUsersScreen(topPadding: 0),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
    expect(issuesRead, isFalse);
    expect(usersRead, isFalse);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeSeerrService service,
  required Widget screen,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) =>
              settingsWith(seerrUrl: 'https://seerr.test', seerrApiKey: 'key'),
        ),
        seerrServiceProvider.overrideWith((ref) => service),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
