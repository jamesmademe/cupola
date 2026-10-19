import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';

import '../../../test_helpers/fake_api_client.dart';

typedef _Read = (String, ProviderListenable<AsyncValue<Object?>>);

/// The reads the Readout rail and the Overview wait on: the sources, and every
/// provider derived from one. A derived read under the default policy waits out
/// the backoff of the source it awaits, so the five go together.
final List<_Read> _reads = [
  ('badges', bazarrBadgesProvider),
  ('dashboard wanted', bazarrDashboardWantedProvider),
  ('dashboard history', bazarrDashboardHistoryProvider),
  ('overview wanted', bazarrOverviewWantedProvider),
  ('overview history', bazarrOverviewHistoryProvider),
];

/// A source under Riverpod's default policy: the harness's own control.
final _defaultRetryBadges = FutureProvider<BazarrBadges>(
  (ref) => ref.watch(bazarrServiceProvider).getBadges(),
);

/// Shorter than Riverpod's first retry delay (200 ms): a provider that is
/// going to retry is still reporting *loading* at this point.
const _settle = Duration(milliseconds: 50);

/// A Bazarr that went dark: every GET fails the way a refused connection does.
/// `getCallCount` counts attempts, and a retry is an attempt.
FakeApiClient _darkBazarr() => FakeApiClient()
  ..getException = DioException(
    requestOptions: RequestOptions(path: '/api'),
    type: DioExceptionType.connectionError,
    message: 'Connection refused',
  );

ProviderContainer _containerOver(FakeApiClient api) {
  // No `retry:` on the container, deliberately: the policy under test is the
  // one each provider declares, and a container-wide override would hide it.
  final container = ProviderContainer(
    overrides: [bazarrServiceProvider.overrideWithValue(BazarrService(api))],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('control: under the default policy a dark Bazarr spins', (
    tester,
  ) async {
    // Proves the harness can see a retry at all, so the test below is not
    // passing because nothing would ever have retried.
    final api = _darkBazarr();
    final container = _containerOver(api);
    container.listen(_defaultRetryBadges, (_, _) {});

    await tester.pump(_settle);
    expect(container.read(_defaultRetryBadges).isLoading, isTrue);

    await tester.pump(const Duration(minutes: 1));
    expect(api.getCallCount, greaterThan(1));
  });

  testWidgets('every read settles on its first failure and is not retried', (
    tester,
  ) async {
    final api = _darkBazarr();
    final container = _containerOver(api);
    for (final (_, provider) in _reads) {
      container.listen(provider, (_, _) {});
    }

    await tester.pump(_settle);
    for (final (name, provider) in _reads) {
      final state = container.read(provider);
      expect(state.isLoading, isFalse, reason: '$name is still loading');
      expect(state.hasError, isTrue, reason: '$name did not reach its error');
    }

    final attempts = api.getCallCount;
    await tester.pump(const Duration(minutes: 1));
    expect(api.getCallCount, attempts, reason: 'something retried on its own');
    for (final (name, provider) in _reads) {
      expect(container.read(provider).hasError, isTrue, reason: name);
    }
  });
}
