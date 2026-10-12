import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/settings_scope.dart';

/// A server that is down. `noSuchMethod` stands in for the rest of the client:
/// this is about how a failure travels, not about what the client can do.
class _DarkNzbget implements NzbgetClient {
  @override
  Future<NzbgetStatus> status() async => throw _refused('status');

  @override
  Future<List<NzbgetGroup>> listGroups() async => throw _refused('listgroups');

  @override
  Future<List<NzbgetHistoryItem>> history({bool hidden = false}) async =>
      throw _refused('history');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DioException _refused(String method) => DioException(
  requestOptions: RequestOptions(path: '/jsonrpc/$method'),
  message: 'connection refused',
);

void main() {
  // Riverpod's default retry re-runs a failed build ten times behind an
  // exponential backoff, and the part that costs something: the future does
  // not settle until it has. A dark NZBGet therefore left every one of these
  // pending for roughly forty seconds: no error, no unreachable band, a
  // spinner. `retry: noProviderRetry` is what makes the failure arrive at the
  // first attempt, where the surface can draw it and offer its own Retry.
  //
  // (The "not configured" throw never needed this: it comes out of `ref.watch`
  // as a `ProviderException`, which `ProviderContainer.defaultRetry` declines
  // on its own. This test is about the server that answers nothing.)
  test('a dark NZBGet reaches its screens on the first attempt', () async {
    final container = ProviderContainer(
      overrides: [
        // The queue provider resolves which connection it reads for the read
        // clock, so a container that runs it needs settings.
        currentSettingsProvider.overrideWith(
          (ref) => settingsWith(nzbgetUrl: 'http://nzbget.test'),
        ),
        nzbgetClientProvider.overrideWithValue(_DarkNzbget()),
      ],
    );
    addTearDown(container.dispose);

    for (final future in [
      container.read(nzbgetStatusProvider.future),
      container.read(nzbgetQueueProvider.future),
      container.read(nzbgetHistoryProvider.future),
    ]) {
      await expectLater(
        future.timeout(const Duration(milliseconds: 300)),
        throwsA(isA<DioException>()),
      );
    }
  });
}
