import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Long-lived Socket.IO client for Dockge, rebuilt when its URL/credentials
/// change. Closed automatically when disposed.
final dockgeClientProvider = Provider<DockgeClient>((ref) {
  // One `watchTransport` in place of four hand-written selects, and it is the
  // only one of the five that follows the lens: the four read `dockgeUrl` and
  // friends, which are always the first connection, so a second Dockge could be
  // named in the app bar and never reached.
  final transport = watchTransport(ref, ServiceKey.dockge);
  if (transport.url.isEmpty) {
    throw const DockgeException('Dockge not configured');
  }
  final client = DockgeClient(
    baseUrl: transport.url,
    username: transport.username.isEmpty ? null : transport.username,
    password: transport.apiKey.isEmpty ? null : transport.apiKey,
    certFingerprint: transport.pin,
  );
  ref.onDispose(client.close);
  return client;
});

/// Which Dockge instance the app is looking through: the empty string for the
/// hub this login belongs to, an agent's `host:port` otherwise.
///
/// This is the app-bar connection lens, not a tab (decision 41). It is a Dockge
/// concept rather than a Cupola one — one login, several instances relayed
/// through it — so it lives beside the client instead of in the settings lens,
/// which picks between *connections* the user configured.
class DockgeAgentLens extends Notifier<String> {
  @override
  String build() => DockgeAgent.local.endpoint;

  void select(String endpoint) {
    if (state == endpoint) return;
    state = endpoint;
  }
}

final dockgeSelectedAgentProvider = NotifierProvider<DockgeAgentLens, String>(
  DockgeAgentLens.new,
);

/// The client with the lens applied.
///
/// Every read and every write goes through this rather than
/// [dockgeClientProvider], so moving the lens re-points the socket's `agent`
/// envelope once, in one place, instead of each call site remembering to pass
/// an endpoint. Watching both means a client rebuilt for a new URL comes back
/// already pointed at the selected agent.
final dockgeLensedClientProvider = Provider<DockgeClient>((ref) {
  final client = ref.watch(dockgeClientProvider);
  client.selectAgent(ref.watch(dockgeSelectedAgentProvider));
  return client;
});

/// Every instance reachable through this login, the hub first.
///
/// Seeded with whatever the client already holds so the lens has something to
/// draw before the first push; a Dockge without the multi-agent feature never
/// pushes at all, and the seed is the correct final answer there.
final dockgeAgentsProvider = StreamProvider.autoDispose<List<DockgeAgent>>((
  ref,
) async* {
  final client = ref.watch(dockgeClientProvider);
  await client.ensureConnected();
  yield client.latestAgents;
  yield* client.agentListStream;
});

final dockgeServiceProvider = Provider<DockgeService>((ref) {
  return DockgeService(ref.watch(dockgeLensedClientProvider));
});

/// Live stack list — connects, requests a refresh, then streams every push
/// Dockge sends (`stackList` / `stackStatusList`).
final dockgeStackListProvider = StreamProvider.autoDispose<List<DockgeStack>>((
  ref,
) async* {
  final client = ref.watch(dockgeLensedClientProvider);
  await client.ensureConnected();
  if (client.latestStacks.isNotEmpty) {
    yield client.latestStacks;
  }
  unawaited(client.requestStackList());
  yield* client.stackListStream;
});

/// Full detail (compose YAML/ENV) for a single stack.
final dockgeStackDetailProvider = FutureProvider.autoDispose
    .family<DockgeStackDetail, String>((ref, name) async {
      return ref.watch(dockgeServiceProvider).getStack(name);
    });

/// Per-service container status for a single stack.
final dockgeServiceStatusProvider = FutureProvider.autoDispose
    .family<List<DockgeServiceStatus>, String>((ref, name) async {
      return ref.watch(dockgeServiceProvider).getServiceStatusList(name);
    });
