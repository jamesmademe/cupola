import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The commands the client relays, over the app's own Socket.IO client
/// against the world's Dockge: what reaches the server by name, and what a
/// refusal from it becomes.
void main() {
  Future<(ProfileHarness, DockgeClient)> start({
    ConnectionBehaviour? behaviour,
  }) async {
    final profile = behaviour == null
        ? Profiles.p1
        : Profiles.p1.withBehaviour(WorldIds.dockge, behaviour);
    final harness = await ProfileHarness.start(profile);
    final client = harness.container().read(dockgeClientProvider);
    addTearDown(client.close);
    return (harness, client);
  }

  /// The relayed commands Dockge received, in order, without the login and
  /// the list the client asks for on its own.
  List<String> commands(ProfileHarness harness) => [
    for (final (id, call) in harness.network.rpcCalls)
      if (id == WorldIds.dockge &&
          call.startsWith('agent:') &&
          call != 'agent:requestStackList')
        call.substring('agent:'.length),
  ];

  test(
    'each stack and service action reaches Dockge by its own name',
    () async {
      final (harness, client) = await start();

      await client.startStack('media');
      await client.stopStack('media');
      await client.restartStack('media');
      await client.updateStack('media');
      await client.downStack('media');
      await client.startService('media', 'radarr');
      await client.stopService('media', 'radarr');
      await client.restartService('media', 'radarr');
      await client.deleteStack('media');

      expect(commands(harness), [
        'startStack',
        'stopStack',
        'restartStack',
        'updateStack',
        'downStack',
        'startService',
        'stopService',
        'restartService',
        'deleteStack',
      ]);
    },
  );

  test('a stack is read with its compose file', () async {
    final (harness, client) = await start();

    final detail = await client.getStack('media');
    final services = await client.getServiceStatusList('media');

    expect(detail.name, 'media');
    expect(detail.composeYAML.trim(), 'services: {}');
    expect(services, isEmpty);
    expect(commands(harness), ['getStack', 'serviceStatusList']);
  });

  test('a command Dockge refuses fails with the server\'s own words', () async {
    final (_, client) = await start(behaviour: ConnectionBehaviour.readOnly);

    await expectLater(
      client.stopStack('media'),
      throwsA(
        isA<DockgeException>().having(
          (error) => error.message,
          'message',
          'Permission denied',
        ),
      ),
    );
  });

  test('a refused login fails as unauthorised, never as a timeout', () async {
    final (_, client) = await start(behaviour: ConnectionBehaviour.refusesKey);

    await expectLater(
      client.ensureConnected(),
      throwsA(
        isA<DockgeException>().having(
          (error) => error.message,
          'message',
          'Incorrect username or password.',
        ),
      ),
    );
  });
}
