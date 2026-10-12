import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/settings_scope.dart';

class _DarkSabnzbd implements SabnzbdClient {
  @override
  Future<SabnzbdQueue> getQueue({int limit = 50}) async =>
      throw _refused('queue');

  @override
  Future<List<SabnzbdHistorySlot>> getHistory({int limit = 20}) async =>
      throw _refused('history');

  @override
  Future<SabnzbdServerStats> getServerStats() async =>
      throw _refused('server_stats');

  @override
  Future<List<String>> getCategories() async => throw _refused('get_cats');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _refused(String mode) => DioException(
  requestOptions: RequestOptions(path: '/api?mode=$mode'),
  message: 'connection refused',
);

void main() {
  // The same rule the NZBGet retry test states: ten backing-off retries hold
  // the future, so a dark SABnzbd is a spinner rather than an unreachable
  // band. See `noProviderRetry`.
  test('a dark SABnzbd reaches its screens on the first attempt', () async {
    final container = ProviderContainer(
      overrides: [
        // The queue provider resolves which connection it reads for the read
        // clock, so a container that runs it needs settings.
        currentSettingsProvider.overrideWith(
          (ref) =>
              settingsWith(sabnzbdUrl: 'http://sab.test', sabnzbdApiKey: 'key'),
        ),
        sabnzbdClientProvider.overrideWithValue(_DarkSabnzbd()),
      ],
    );
    addTearDown(container.dispose);

    for (final future in [
      container.read(sabnzbdQueueProvider.future),
      container.read(sabnzbdHistoryProvider.future),
      container.read(sabnzbdServerStatsProvider.future),
      container.read(sabnzbdCategoriesProvider.future),
    ]) {
      await expectLater(
        future.timeout(const Duration(milliseconds: 300)),
        throwsA(isA<DioException>()),
      );
    }
  });
}
