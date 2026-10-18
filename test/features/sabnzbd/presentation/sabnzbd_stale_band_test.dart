import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/queue_stale_scenarios.dart';

void main() {
  defineQueueStaleScenarios(
    QueueStaleCase(
      service: ServiceKey.sabnzbd,
      profile: Profiles.p1,
      connectionId: WorldIds.sabnzbd,
      screen: () => const SabnzbdScreen(showAppBar: false),
      // The whole queue the page draws (`limit=0`), not the one-slot read the
      // connection's probe makes, which must keep answering.
      isQueueRead: (request) =>
          request.query['mode'] == 'queue' &&
          request.query['limit'] == '0' &&
          !request.query.containsKey('name'),
    ),
  );
}
