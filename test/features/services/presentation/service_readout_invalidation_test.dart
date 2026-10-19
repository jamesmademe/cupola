import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

/// A Bazarr whose provider list fails the first time it is asked, the way a
/// transient `/api/providers` error does, and answers from then on.
class _FlakyProvidersBazarr extends BazarrService {
  _FlakyProvidersBazarr() : super(FakeApiClient());

  int statusReads = 0;

  @override
  Future<BazarrBadges> getBadges() async => const BazarrBadges(
    episodes: 3,
    movies: 1,
    providers: 0,
    status: true,
    sonarrSignalR: true,
    radarrSignalR: true,
    announcements: 0,
  );

  @override
  Future<List<BazarrProviderStatus>> getProviderStatuses() async {
    if (++statusReads == 1) throw Exception('providers unavailable');
    return const [BazarrProviderStatus(name: 'OpenSubtitles', status: 'Good')];
  }
}

void main() {
  testWidgets(
    'a pull re-reads the Bazarr provider statuses the rail folds in',
    (tester) async {
      final bazarr = _FlakyProvidersBazarr();
      late WidgetRef ref;
      late AsyncValue<Object?> rail;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => settingsWith(
                bazarrUrl: 'http://bazarr.lan:6767',
                bazarrApiKey: 'key',
              ),
            ),
            bazarrServiceProvider.overrideWith((ref) => bazarr),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, widgetRef, _) {
                ref = widgetRef;
                rail = widgetRef.watch(serviceKpiProvider(ServiceKey.bazarr));
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The statuses are kept for the life of the app, so the failure stays.
      expect(rail.hasError, isTrue);
      expect(bazarr.statusReads, 1);

      invalidateServiceReadout(ref, ServiceKey.bazarr);
      await tester.pumpAndSettle();

      expect(bazarr.statusReads, 2);
      expect(rail.hasError, isFalse);
      expect(rail.hasValue, isTrue);
    },
  );
}
