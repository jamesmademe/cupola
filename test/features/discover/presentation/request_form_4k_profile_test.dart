import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/request_form_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The request sheet against P6's Seerr, which sends to Radarr (server 0) and
/// to Radarr 4K (server 1, the default 4K server).
void main() {
  const args = (
    mediaId: 45745,
    mediaType: 'movie',
    copies: SeerrRequestCopies.both,
  ); // Sintel

  /// Until the sheet has its servers and profiles. The fake network answers
  /// at once, but each request takes a few turns of the event loop through
  /// the client's interceptors, so a fixed count of turns is a guess.
  Future<void> settle(ProviderContainer container) async {
    for (var i = 0; i < 500; i++) {
      await Future<void>.delayed(Duration.zero);
      if (!container.read(requestFormProvider(args)).isLoading) return;
    }
  }

  Future<(ProfileHarness, ProviderContainer)> open() async {
    final harness = await ProfileHarness.start(Profiles.p6);
    final container = harness.container(retry: (_, _) => null);
    final subscription = container.listen<RequestFormState>(
      requestFormProvider(args),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await settle(container);
    return (harness, container);
  }

  Map<String, Object?> sentBody(ProfileHarness harness) {
    final posts = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.method == 'POST' && r.uri.path == '/api/v1/request');
    return (jsonDecode(posts.single.body) as Map).cast<String, Object?>();
  }

  test('P6: both servers are offered, the 4K one named as such', () async {
    final (_, container) = await open();
    final state = container.read(requestFormProvider(args));

    expect(state.servers.map((s) => s.choiceLabel), ['Radarr', 'Radarr 4K']);
    expect(state.selectedServer?.name, 'Radarr');
  });

  test('P6: a standard request says so and names its server', () async {
    final (harness, container) = await open();

    expect(
      await container.read(requestFormProvider(args).notifier).submitRequest(),
      isNull,
    );
    expect(sentBody(harness), containsPair('is4k', false));
    expect(sentBody(harness), containsPair('serverId', 0));
  });

  test('P6: a request sent to Radarr 4K is a 4K request', () async {
    final (harness, container) = await open();
    final notifier = container.read(requestFormProvider(args).notifier);

    notifier.selectServer(1);
    await Future<void>.delayed(Duration.zero);
    await settle(container);
    expect(await notifier.submitRequest(), isNull);

    // It was filed on the 4K server without `is4k`: a standard request that
    // Seerr then tracked on the HD copy of the title.
    expect(sentBody(harness), containsPair('is4k', true));
    expect(sentBody(harness), containsPair('serverId', 1));
    expect(sentBody(harness), containsPair('profileId', 1));
    expect(
      sentBody(harness),
      containsPair('rootFolder', '/mnt/tank/media/films-4k'),
    );
  });
}
