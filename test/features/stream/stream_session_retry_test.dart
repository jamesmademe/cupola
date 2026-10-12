import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// A media server that is down, and counts how many times it was asked.
///
/// `noSuchMethod` stands in for the rest of [StreamServerClient]: this test is
/// about one call, and listing the other eight would say nothing.
class _DarkServer implements StreamServerClient {
  int calls = 0;

  @override
  Future<List<StreamSession>> getSessions() async {
    calls++;
    throw DioException(
      requestOptions: RequestOptions(path: '/Sessions'),
      message: 'connection refused',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a dark media server is asked once, not ten times', () async {
    final client = _DarkServer();
    final container = ProviderContainer(
      overrides: [jellyfinServerProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(jellyfinSessionsProvider.future),
      throwsA(isA<DioException>()),
    );

    // The whole point of `retry: noProviderRetry`. Riverpod's default would run
    // this ten times behind an exponential backoff, and the part that costs
    // something: the future would not settle until it had. `streamActivity`
    // awaits it inside a `try` written to carry on without this server, walking
    // the media servers one at a time, so those forty seconds are spent before
    // Plex is even asked.
    expect(
      client.calls,
      1,
      reason: 'the failure has to reach the caller on the first attempt',
    );
  });
}
