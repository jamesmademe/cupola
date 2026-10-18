import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/queue_stale_scenarios.dart';

void main() {
  defineQueueStaleScenarios(
    QueueStaleCase(
      service: ServiceKey.nzbget,
      profile: Profiles.p1
          .withConnection(WorldConnections.nzbget)
          .withDownloads(const [
            WorldDownload(
              id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345611',
              release: 'Tears.of.Steel.2012.2160p.WEB',
              client: 'nzbget',
              state: DownloadState.downloading,
              progress: 0.4,
              size: 4 * 1024 * 1024 * 1024,
              speed: 8 * 1024 * 1024,
              eta: Duration(minutes: 7),
            ),
          ]),
      connectionId: 'nzbget',
      screen: () => const NzbgetScreen(showAppBar: false),
      isQueueRead: (request) {
        final body = request.json;
        return body is Map && body['method'] == 'listgroups';
      },
    ),
  );
}
