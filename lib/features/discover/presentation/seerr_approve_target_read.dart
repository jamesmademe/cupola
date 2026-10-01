import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How long the approve confirmation waits to name its server. Past it the
/// confirmation says what it knows: the request goes to Seerr's Radarr.
const Duration seerrTargetReadLimit = Duration(seconds: 4);

/// The kind of server a request of [request]'s type goes to.
ServiceKey seerrArrFor(SeerrRequest request) =>
    request.type == 'tv' ? ServiceKey.sonarr : ServiceKey.radarr;

/// Where approving [request] on the Seerr [instanceId] sends it.
///
/// Seerr's server list is asked for each time rather than kept: it is one
/// small read beside a write, and a list kept from an earlier failure would
/// go on saying the server is unknown after Seerr came back. A list that
/// does not arrive within [seerrTargetReadLimit] leaves the target unknown,
/// never a server Seerr does not have.
///
/// Everything [ref] gives is read before the wait, so a row that scrolls
/// away meanwhile is never asked for its ref afterwards.
Future<SeerrApproveTarget> readSeerrApproveTarget(
  WidgetRef ref, {
  required String instanceId,
  required SeerrRequest request,
}) async {
  final arr = seerrArrFor(request);
  final service = ref.read(seerrServiceForProvider(instanceId));
  final connections = ref
      .read(currentSettingsProvider)
      .configuredInstancesOf(arr);
  List<SeerrArrServer>? servers;
  try {
    servers = await service.getArrServers(arr).timeout(seerrTargetReadLimit);
  } catch (_) {
    servers = null;
  }
  return SeerrApproveTarget.of(
    request,
    servers: servers,
    connections: connections,
  );
}
