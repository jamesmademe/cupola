import 'dart:async';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';

/// Thin facade over [DockgeClient] for one-shot, request/response style reads
/// (used by KPI and status aggregation). Live views should watch the client's
/// [DockgeClient.stackListStream] directly instead.
class DockgeService {
  final DockgeClient client;

  DockgeService(this.client);

  /// Connects (if needed) and returns the current stack list, requesting a
  /// fresh push when none has been received yet.
  Future<List<DockgeStack>> fetchStacks() async {
    await client.ensureConnected();
    // The last push may be from a connection that has since closed (a Dockge
    // read after an idle close): ask this connection for its list. The cached
    // one answers only when the server stays silent past the short wait, so a
    // live server never shows a list from before the reconnect.
    final cached = client.latestStacks;
    final next = client.stackListStream.first.timeout(
      const Duration(seconds: 5),
    );
    // Only the push counts; the acknowledgement carries nothing, and a failed
    // one surfaces as the missing push below.
    client.requestStackList().ignore();
    try {
      return await next;
    } on TimeoutException {
      if (cached.isNotEmpty) return cached;
      // A silent server is not an empty one. Answering the deadline with `[]`
      // put "0 stacks" on the card for a Dockge that never said how many it had.
      throw const DockgeException('Dockge did not return its stack list');
    }
  }

  Future<DockgeStackDetail> getStack(String name) => client.getStack(name);

  Future<List<DockgeServiceStatus>> getServiceStatusList(String name) =>
      client.getServiceStatusList(name);

  /// Connects and returns the reported Dockge version (null if unavailable).
  Future<String?> fetchVersion() async {
    await client.ensureConnected();
    return client.version;
  }
}
