import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_providers_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_bazarr_service.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('lists every enabled provider, and the throttled one in its '
      'reason\'s words with when Bazarr asks again', (tester) async {
    final service = FakeBazarrService()
      ..providerStatuses = const [
        BazarrProviderStatus(
          name: 'opensubtitlescom',
          status: 'TooManyRequests',
          retry: 'in 2 hours',
        ),
        BazarrProviderStatus(name: 'podnapisi', status: 'Good', retry: '-'),
      ];
    await _pump(tester, service: service);

    expect(find.text('2 enabled\u00A0· 1 throttled'), findsOneWidget);
    expect(find.text('OpenSubtitles.com'), findsOneWidget);
    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.text('in 2 hours'), findsOneWidget);
    expect(find.text('Podnapisi'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        'OpenSubtitles.com, Too many requests, asks again in 2 hours',
      ),
      findsOneWidget,
    );
    expect(find.semantics.byLabel('Podnapisi, Ready'), findsOneWidget);

    // Asks first, and Cancel sends nothing.
    await tester.tap(
      find.byKey(const ValueKey('bazarr-reset-provider-throttles')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reset provider throttles?'), findsOneWidget);
    expect(
      find.textContaining('stops waiting out 1 throttled provider'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.resetProviderStatusesCalled, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('bazarr-reset-provider-throttles')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Reset throttles'),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.resetProviderStatusesCalled, isTrue);
    expect(find.text('Provider throttles reset'), findsOneWidget);
  });

  testWidgets('nothing throttled offers no reset', (tester) async {
    await _pump(
      tester,
      service: FakeBazarrService()
        ..providerStatuses = const [
          BazarrProviderStatus(name: 'podnapisi', status: 'Good', retry: '-'),
        ],
    );

    expect(find.text('1 enabled'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bazarr-reset-provider-throttles')),
      findsNothing,
    );
  });

  testWidgets('a Bazarr with no provider enabled says it finds no subtitles', (
    tester,
  ) async {
    await _pump(tester, service: FakeBazarrService());

    expect(find.text('0 enabled'), findsOneWidget);
    expect(find.text('No providers enabled'), findsOneWidget);
    expect(find.textContaining('finds no subtitles'), findsOneWidget);
  });

  testWidgets(
    'does not read the provider endpoint when Bazarr is unconfigured',
    (tester) async {
      final service = FakeBazarrService();
      await _pump(tester, service: service, configured: false);

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.text('No providers enabled'), findsNothing);
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeBazarrService service,
  bool configured = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  bazarrUrl: 'https://bazarr.test',
                  bazarrApiKey: 'key',
                )
              : const SettingsModel(),
        ),
        bazarrServiceProvider.overrideWith((ref) => service),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        home: const BazarrProvidersScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
