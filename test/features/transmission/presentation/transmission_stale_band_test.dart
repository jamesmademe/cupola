import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/queue_stale_scenarios.dart';

void main() {
  defineQueueStaleScenarios(
    QueueStaleCase(
      service: ServiceKey.transmission,
      profile: Profiles.p4,
      connectionId: WorldIds.transmission,
      screen: () => const TransmissionScreen(showAppBar: false),
      isQueueRead: (request) {
        final body = request.json;
        return body is Map && body['method'] == 'torrent-get';
      },
    ),
  );
}
