import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How long the approve confirmation waits, all told, to say where a request
/// goes. One budget for every read it makes: past it the confirmation says
/// what it knows, and the person is never kept waiting longer than this.
const Duration seerrTargetReadLimit = Duration(seconds: 4);

/// The kind of server a request of [request]'s type goes to.
ServiceKey seerrArrFor(SeerrRequest request) =>
    request.type == 'tv' ? ServiceKey.sonarr : ServiceKey.radarr;

/// What the approve confirmation could read in its budget: the request, when
/// it was known or arrived, where it goes, when the request is known, and
/// Seerr's servers for its kind, when they arrived: the ones it may be sent
/// to instead.
typedef SeerrApproveRead = ({
  SeerrRequest? request,
  SeerrApproveTarget? target,
  List<SeerrArrServer>? servers,
});

/// Where approving the request [requestId] on the Seerr [instanceId] sends
/// it, read within one [budget].
///
/// [request] is the record when the caller holds it; otherwise it is read
/// first (`GET /api/v1/request/{id}`), then Seerr's server list for its kind.
/// Both reads share the budget: it used to be one cap each, so a slow Seerr
/// held the confirmation for twice as long with nothing on screen. What has
/// arrived when the budget runs out is what the confirmation says: a request
/// with no server list reads as going to Seerr's Radarr, never to a server
/// Seerr does not have.
///
/// Seerr's server list is asked for each time rather than kept: it is one
/// small read beside a write, and a list kept from an earlier failure would
/// go on saying the server is unknown after Seerr came back.
///
/// Everything [ref] gives is read before the wait, so a row that scrolls away
/// meanwhile is never asked for its ref afterwards.
Future<SeerrApproveRead> readSeerrApproveTarget(
  WidgetRef ref, {
  required String instanceId,
  required int requestId,
  SeerrRequest? request,
  Duration budget = seerrTargetReadLimit,
}) async {
  final service = ref.read(seerrServiceForProvider(instanceId));
  final settings = ref.read(currentSettingsProvider);

  var known = request;
  List<SeerrArrServer>? servers;
  Future<void> read() async {
    final found = known ?? await service.getRequest(requestId);
    known = found;
    servers = await service.getArrServers(seerrArrFor(found));
  }

  try {
    await read().timeout(budget);
  } catch (_) {
    // Out of budget, or a read that failed: what arrived is all there is.
  }

  final readRequest = known;
  if (readRequest == null) {
    return (request: null, target: null, servers: null);
  }
  final arr = seerrArrFor(readRequest);
  return (
    request: readRequest,
    target: SeerrApproveTarget.of(
      readRequest,
      servers: servers,
      connections: settings.configuredInstancesOf(arr),
    ),
    servers: servers,
  );
}
