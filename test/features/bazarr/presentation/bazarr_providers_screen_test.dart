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
  testWidgets('shows the aggregate and throttled provider status', (
    tester,
  ) async {
    final service = FakeBazarrService()
      ..providerSummary = const BazarrProviderSummary(configuredCount: 5)
      ..providerStatuses = const [
        BazarrProviderStatus(
          name: 'OpenSubtitles',
          status: 'Too many requests',
          retry: '2026-09-18 15:00',
        ),
      ];
    await _pump(tester, service: service);

    expect(find.text('5 configured'), findsOneWidget);
    expect(find.text('Configured providers'), findsOneWidget);
    expect(find.text('OpenSubtitles'), findsOneWidget);
    expect(find.text('Too many requests'), findsOneWidget);
    expect(find.text('2026-09-18 15:00'), findsOneWidget);
    expect(
      find.semantics.byLabel(
        'OpenSubtitles, Too many requests, retry 2026-09-18 15:00',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('bazarr-reset-provider-throttles')),
    );
    await tester.pumpAndSettle();
    expect(service.resetProviderStatusesCalled, isTrue);
    expect(find.text('Provider throttles reset'), findsOneWidget);
  });

  testWidgets(
    'does not read the provider endpoint when Bazarr is unconfigured',
    (tester) async {
      final service = FakeBazarrService();
      await _pump(tester, service: service, configured: false);

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.text('Configured providers'), findsNothing);
    },
  );

  testWidgets('renders an em dash when the supported response has no count', (
    tester,
  ) async {
    await _pump(
      tester,
      service: FakeBazarrService()
        ..providerSummary = const BazarrProviderSummary(),
    );

    expect(find.text('—'), findsNWidgets(2));
  });
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
