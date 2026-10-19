import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/activity_blocklist_page.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

ActivityServiceResult _answered(ServiceKey service, int? total) =>
    ActivityServiceResult(
      service: service,
      items: const [],
      configured: true,
      total: total,
    );

ActivityFeed _feed(List<ActivityServiceResult> results) =>
    ActivityFeed(items: const [], results: results);

/// The line under the Blocklist's name: what the arrs keep blocked, summed
/// from their own totals, and a floor whenever a term is missing.
void main() {
  test('the servers\' totals, summed', () {
    expect(
      blocklistCountOf(
        _feed([
          _answered(ServiceKey.radarr, 9),
          _answered(ServiceKey.sonarr, 3),
        ]),
      ),
      (count: 12, floor: false),
    );
  });

  test('a server that did not answer makes the sum a floor', () {
    expect(
      blocklistCountOf(
        _feed([
          _answered(ServiceKey.radarr, 9),
          ActivityServiceResult(
            service: ServiceKey.sonarr,
            items: const [],
            configured: true,
            error: Exception('down'),
          ),
        ]),
      ),
      (count: 9, floor: true),
    );
  });

  test('a server that gave no total, or stopped short, is a floor too', () {
    expect(
      blocklistCountOf(_feed([_answered(ServiceKey.radarr, null)])),
      isNull,
      reason: 'no rows and no total: nothing to say',
    );
    expect(
      blocklistCountOf(
        _feed([
          const ActivityServiceResult(
            service: ServiceKey.radarr,
            items: [],
            configured: true,
            total: 200,
            cutShort: true,
          ),
        ]),
      ),
      (count: 200, floor: true),
    );
  });

  test('nothing blocked says nothing: the empty list says it', () {
    expect(blocklistCountOf(_feed([_answered(ServiceKey.radarr, 0)])), isNull);
  });
}
