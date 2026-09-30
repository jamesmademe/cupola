@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/fault_band.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'FaultBand',
    scenes: [
      CatalogScene(
        '.unreachable(since: 6 min) · Retry · Settings, the age turns the '
        'sentence into a measurement',
        (_) => FaultBand.unreachable(
          serviceName: 'TrueNAS',
          since: const Duration(minutes: 6),
          onRetry: () {},
          onOpenSettings: () {},
        ),
      ),
      CatalogScene(
        '.unreachable(since: null) · under a minute, the span is dropped '
        'rather than printing a number nobody can act on',
        (_) => FaultBand.unreachable(serviceName: 'Radarr', onRetry: () {}),
      ),
      CatalogScene(
        '.fault(reason: unauthorized) · the service answered and refused the '
        'key: amber, Retry · the remedy',
        (_) => FaultBand.fault(
          serviceName: 'Radarr',
          reason: ServiceFailureReason.unauthorized,
          onRetry: () {},
          onOpenSettings: () {},
        ),
      ),
      CatalogScene(
        '.section · the caller\'s own sentence naming which source is '
        'missing, Retry only',
        (_) => FaultBand.section(
          message:
              'Radarr is answering. qBittorrent, the download client it '
              'hands grabs to, is not — so the queue is missing from this '
              'page.',
          onRetry: () {},
        ),
      ),
      CatalogScene(
        '.partial · the service answered part of a paged read: amber, never '
        'red, Retry only',
        (_) => FaultBand.partial(
          message:
              'Seerr returned 50 of 300 users; later pages are unavailable.',
          onRetry: () {},
        ),
      ),
      CatalogScene(
        '.stale(age: 6 min) · warning tone, Refresh only, no dismiss',
        (_) => FaultBand.stale(
          age: const Duration(minutes: 6),
          detail: 'TrueNAS live metrics have not returned.',
          onRefresh: () {},
        ),
      ),
      CatalogScene(
        '.stale(age: just now) · the clock-tick edge case still reads as a '
        'sentence',
        (_) => FaultBand.stale(
          age: const Duration(seconds: 20),
          detail: 'TrueNAS live metrics have not returned.',
          onRefresh: () {},
        ),
      ),
      CatalogScene(
        '.offlinePush · Retry · Open Radarr, the render stays because it is '
        'the last true thing the app knows',
        (_) => FaultBand.offlinePush(
          serviceName: 'Radarr',
          onRetry: () {},
          onOpen: () {},
        ),
      ),
    ],
  );
}
