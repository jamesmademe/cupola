import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
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

final dockgeServiceProvider = Provider<DockgeService>((ref) {
  return DockgeService(ref.watch(dockgeClientProvider));
});

/// Live stack list — connects, requests a refresh, then streams every push
/// Dockge sends (`stackList` / `stackStatusList`).
final dockgeStackListProvider = StreamProvider.autoDispose<List<DockgeStack>>((
  ref,
) async* {
  final client = ref.watch(dockgeClientProvider);
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
