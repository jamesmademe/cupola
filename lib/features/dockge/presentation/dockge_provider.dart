import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// Long-lived Socket.IO client for Dockge, rebuilt when its URL/credentials
/// change. Closed automatically when disposed.
final dockgeClientProvider = Provider<DockgeClient>((ref) {
  // One `watchTransport` in place of four hand-written selects, and it is the
  // only one of the five that follows the lens: the four read `dockgeUrl` and
  // friends, which are always the first connection, so a second Dockge could be
  // named in the app bar and never reached.
  final transport = watchTransport(ref, ServiceKey.dockge);
  if (transport.url.isEmpty) {
    throw const ServiceNotConfigured(ServiceKey.dockge);
  }
  final client = DockgeClient(
    baseUrl: transport.url,
    username: transport.username.isEmpty ? null : transport.username,
    password: transport.apiKey.isEmpty ? null : transport.apiKey,
    certFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
    onlyAtHome: transport.onlyAtHomeOf(ServiceKey.dockge),
  );
  ref.onDispose(client.close);
  return client;
});

/// Dockge client bound to one configured connection.
///
/// Empty and active ids intentionally collapse to [dockgeClientProvider], so
/// the ordinary lens remains the single owner of the live connection. A
/// non-active id is built directly from its transport and never reads the
/// agent lens: agent selection belongs to the Dockge login, not to the
/// settings connection id.
final dockgeClientForProvider = Provider.family<DockgeClient, String>((
  ref,
  instanceId,
) {
  final activeId =
      ref.read(activeInstanceProvider(ServiceKey.dockge))?.id ?? '';
  if (instanceId.isEmpty || instanceId == activeId) {
    return ref.watch(dockgeClientProvider);
  }
  return _dockgeClient(ref, instanceId: instanceId);
});

DockgeClient _dockgeClient(Ref ref, {required String? instanceId}) {
  final transport = watchTransport(
    ref,
    ServiceKey.dockge,
    instanceId: instanceId,
  );
  transport.ensureConfigured(ServiceKey.dockge);
  final client = DockgeClient(
    baseUrl: transport.url,
    username: transport.username.isEmpty ? null : transport.username,
    password: transport.apiKey.isEmpty ? null : transport.apiKey,
    certFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
    onlyAtHome: transport.onlyAtHomeOf(ServiceKey.dockge),
  );
  ref.onDispose(client.close);
  return client;
}

/// Which Dockge instance the app is looking through: the empty string for the
/// hub this login belongs to, an agent's `host:port` otherwise.
///
/// This is the app-bar connection lens, not a tab (decision 41). It is a Dockge
/// concept rather than a Cupola one: one login, several instances relayed
/// through it, so it lives beside the client instead of in the settings lens,
/// which picks between *connections* the user configured.
///
/// Back on the hub whenever the connection lens moves to another Dockge, or
/// the connection is pointed at another address: the agents belong to the
/// login they were listed through, and an endpoint kept across the move is
/// asked of a hub that may not relay it, or relay another machine by that
/// name.
class DockgeAgentLens extends Notifier<String> {
  @override
  String build() {
    ref.watch(
      activeInstanceProvider(
        ServiceKey.dockge,
      ).select((instance) => (instance?.id, instance?.url)),
    );
    return DockgeAgent.local.endpoint;
  }

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

/// One-shot Dockge facade keyed by configured connection id.
///
/// Unlike the live lens facade, this path is suitable for cross-instance KPI
/// reads: an explicit id never uses [dockgeSelectedAgentProvider].
final dockgeServiceForProvider = Provider.family<DockgeService, String>((
  ref,
  instanceId,
) {
  final activeId =
      ref.read(activeInstanceProvider(ServiceKey.dockge))?.id ?? '';
  if (instanceId.isEmpty || instanceId == activeId) {
    return ref.watch(dockgeServiceProvider);
  }
  return DockgeService(ref.watch(dockgeClientForProvider(instanceId)));
});

/// Live stack list: connects, requests a refresh, then streams every push
/// Dockge sends (`stackList` / `stackStatusList`).
final dockgeStackListProvider = StreamProvider.autoDispose<List<DockgeStack>>((
  ref,
) async* {
  final client = ref.watch(dockgeLensedClientProvider);
  await client.ensureConnected();
  if (client.latestStacks.isNotEmpty) {
    yield client.latestStacks;
  }
  // A failed request is not this stream's error: the answer it asks for is a
  // push, and the missing push is what the deadline below reports.
  client.requestStackList().ignore();
  // A broken Dockge can acknowledge `requestStackList` without publishing a
  // list (for example when its Docker daemon socket is missing). Do not leave
  // the Overview skeleton spinning forever while waiting for an event that
  // cannot arrive. A real empty installation publishes an empty list too, so
  // a timeout is an honest transport error rather than an empty-state claim.
  //
  // The deadline is on the **first** list only. `Stream.timeout` measures every
  // gap, and Dockge re-pushes the list on a ten-second cron: a push landing a
  // few milliseconds late turned a healthy stream into this error, the
  // Overview into "Couldn't load Dockge" and the Dashboard card into a shimmer
  // that never resolved, while Retry, reading the cached list, always worked.
  yield* firstEventWithin(
    client.stackListStream,
    const Duration(seconds: 10),
    () => const DockgeException('Dockge did not return its stack list'),
  );
}, retry: noProviderRetry);

/// [source], failing with [onTimeout] only when its **first** event takes longer
/// than [limit]; every later event passes through with no deadline at all.
///
/// The clock stops while the subscription is paused and restarts in full on
/// resume. Riverpod pauses a provider nobody on screen is watching, and a
/// paused broadcast subscription holds its events rather than delivering them,
/// so a clock left running would fail a stream whose answer was sitting in the
/// buffer.
@visibleForTesting
Stream<T> firstEventWithin<T>(
  Stream<T> source,
  Duration limit,
  Object Function() onTimeout,
) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? deadline;
  var answered = false;

  void arm() {
    if (answered) return;
    deadline?.cancel();
    deadline = Timer(limit, () {
      controller.addError(onTimeout());
      subscription?.cancel();
      controller.close();
    });
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = source.listen(
        (event) {
          answered = true;
          deadline?.cancel();
          controller.add(event);
        },
        onError: controller.addError,
        onDone: () {
          deadline?.cancel();
          controller.close();
        },
      );
      arm();
    },
    onPause: () {
      deadline?.cancel();
      subscription?.pause();
    },
    onResume: () {
      subscription?.resume();
      arm();
    },
    onCancel: () {
      deadline?.cancel();
      return subscription?.cancel();
    },
  );
  return controller.stream;
}

/// Full detail (compose YAML/ENV) for a single stack.
final dockgeStackDetailProvider = FutureProvider.autoDispose
    .family<DockgeStackDetail, String>((ref, name) async {
      return ref.watch(dockgeServiceProvider).getStack(name);
    }, retry: noProviderRetry);

/// Per-service container status for a single stack.
final dockgeServiceStatusProvider = FutureProvider.autoDispose
    .family<List<DockgeServiceStatus>, String>((ref, name) async {
      return ref.watch(dockgeServiceProvider).getServiceStatusList(name);
    }, retry: noProviderRetry);

/// Combined stack terminal, accumulated as a bounded tail. Dockge exposes this
/// as output only; there is no shell-input event in its public Socket.IO flow.
///
/// The join is not released when this provider is disposed, because
/// `DockgeClient` has no leave call and inventing a socket event name for one
/// would be guessing at a protocol. Cancelling the subscription stops the app
/// reading the stream; the server keeps sending it until the socket closes.
final dockgeTerminalTextProvider = StreamProvider.autoDispose
    .family<String, String>((ref, stackName) async* {
      final client = ref.watch(dockgeLensedClientProvider);
      await client.ensureConnected();
      final terminalName = client.combinedTerminalName(stackName);
      await client.joinCombinedTerminal(stackName);

      // **Emitted before the loop**, and that is the whole of the fix: a
      // stack whose combined log is quiet sends nothing, so a stream that only
      // yielded from inside `await for` never left `AsyncLoading` and the pane
      // spun forever. Its own "Waiting for output…" branch was unreachable.
      // An empty string is the honest first answer: joined, nothing said yet.
      yield '';

      final tail = TerminalTail();
      await for (final output in client.terminalOutput) {
        if (output.terminalName != terminalName) continue;
        yield tail.append(output.data);
      }
    });

/// A bounded tail of terminal output.
///
/// Terminal chunks arrive small and often. The line count is kept as a running
/// total and the trim only runs when a cap is actually crossed, so an ordinary
/// chunk costs its own length and nothing more. Re-scanning the whole 64 KiB
/// buffer with `allMatches` on every chunk, which is what this replaces, is
/// quadratic work on the UI isolate for output nobody can read that fast.
@visibleForTesting
class TerminalTail {
  static const int _maxChars = 64 * 1024;
  static const int _maxLines = 2000;

  String _text = '';
  int _lines = 0;

  String append(String chunk) {
    // A single frame longer than the whole buffer cannot be useful, and
    // concatenating it before measuring is what makes the cost quadratic.
    if (chunk.length > _maxChars) {
      chunk = chunk.substring(chunk.length - _maxChars);
    }
    _text += chunk;
    _lines += _newlinesIn(chunk);
    if (_text.length <= _maxChars && _lines <= _maxLines) return _text;
    _trim();
    return _text;
  }

  /// Drops whole lines off the front until both caps are met.
  ///
  /// Cutting on a line boundary rather than mid-character keeps the first
  /// visible row readable, and doing both caps in one walk means the character
  /// limit does not cost a second pass.
  void _trim() {
    var cut = 0;
    var lines = _lines;
    while (cut < _text.length &&
        (lines > _maxLines || _text.length - cut > _maxChars)) {
      final next = _text.indexOf('\n', cut);
      if (next < 0) break;
      cut = next + 1;
      lines--;
    }
    // The newline walk is a preference, not the cap. A stream carrying no
    // `\n` at all left `cut` at zero and the buffer grew without bound, and
    // that is not only the hostile case: `docker compose pull` draws its
    // progress with `\r`. Whatever follows the last newline was equally
    // untrimmable once the caps were already met. The sibling implementation
    // in `dockge_stack_detail_screen.dart` still has this hard cut; this class
    // lost it, so the 64 KiB the dartdoc above promises was not enforced.
    if (_text.length - cut > _maxChars) {
      cut = _text.length - _maxChars;
      lines = _newlinesIn(_text.substring(cut));
    }
    if (cut == 0) return;
    _text = _text.substring(cut);
    _lines = lines;
  }

  static int _newlinesIn(String chunk) {
    var count = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk.codeUnitAt(i) == 0x0A) count++;
    }
    return count;
  }
}
