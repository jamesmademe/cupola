import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';

DockgeClient _client() => DockgeClient(baseUrl: 'https://dockge.lan');

void main() {
  group('the agent lens: decision 41', () {
    test('a fresh client is pointed at the hub', () {
      // The empty endpoint is Dockge's own name for "the instance you logged
      // in to", and it is what the `agent` envelope carries for it.
      expect(_client().endpoint, DockgeAgent.local.endpoint);
    });

    test('selecting an agent re-points every command', () {
      final client = _client();

      expect(client.selectAgent('nas:5001'), isTrue);
      expect(client.endpoint, 'nas:5001');
    });

    test('selecting the agent already in view changes nothing', () {
      final client = _client();
      expect(client.selectAgent(''), isFalse);
    });

    test('the combined-terminal name follows the lens', () {
      // Dockge namespaces a stack's aggregated log by endpoint, so a terminal
      // name built from the hub while the lens is on an agent subscribes to a
      // stream that does not exist. This was a `static const ''` before.
      final client = _client();
      expect(client.combinedTerminalName('media'), 'combined--media');

      client.selectAgent('nas:5001');
      expect(client.combinedTerminalName('media'), 'combined-nas:5001-media');
    });

    test('moving the lens drops the previous agent\'s stacks', () {
      // A stack belongs to exactly one agent. Keeping the old rows on screen
      // would offer Start/Stop buttons whose command now goes somewhere the
      // stack does not exist.
      final client = _client();
      client.selectAgent('nas:5001');
      expect(client.latestStacks, isEmpty);
    });

    test('there is always at least one agent to look through', () {
      // A Dockge without the multi-agent feature never pushes an `agentList`.
      // Answering "no instances" there would be a worse lie than "one".
      expect(_client().latestAgents, [DockgeAgent.local]);
    });
  });
}
