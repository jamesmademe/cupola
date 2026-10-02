@Tags(['catalog'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/fault_band.dart';

import 'catalog.dart';

const _access = AccessGatewayAnswer(
  kind: AccessGatewayKind.cloudflareAccess,
  credentialsSent: false,
  gatewayHost: 'cupola-home.cloudflareaccess.com',
  serviceHost: 'radarr.example.com',
);

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
        'key: amber, the remedy first in the amber fill, no Retry',
        (_) => FaultBand.fault(
          serviceName: 'Radarr',
          reason: ServiceFailureReason.unauthorized,
          onRetry: () {},
          onOpenSettings: () {},
        ),
      ),
      CatalogScene(
        '.fault(serviceName: qBittorrent, reason: unauthorized) · a refused '
        'sign-in, in its own words: Sign in again, then Retry, a ban runs out',
        (_) => FaultBand.fault(
          serviceName: 'qBittorrent',
          reason: ServiceFailureReason.unauthorized,
          onRetry: () {},
          onOpenSettings: () {},
        ),
      ),
      CatalogScene(
        '.fault(reason: accessGateway, gateway:) · Cloudflare Access in front '
        'of Radarr, named: Add a service token in the amber fill, no Retry',
        (_) => FaultBand.fault(
          serviceName: 'Radarr',
          reason: ServiceFailureReason.accessGateway,
          gateway: _access,
          onRetry: () {},
          onOpenSettings: () {},
        ),
      ),
      CatalogScene(
        '.fault(reason: serverError) · no form remedy: Retry is the remedy, in '
        'the amber fill',
        (_) => FaultBand.fault(
          serviceName: 'Radarr',
          reason: ServiceFailureReason.serverError,
          onRetry: () {},
        ),
      ),
      CatalogScene(
        '.section · the caller\'s own sentence naming which source is '
        'missing, Retry only',
        (_) => FaultBand.section(
          message:
              'Radarr is answering. qBittorrent, the download client it '
              'hands grabs to, is not, so the queue is missing from this '
              'page.',
          onRetry: () {},
        ),
      ),
      CatalogScene(
        '.partial · the service answered part of a paged read: amber, never '
        'red, Retry only, in the amber fill',
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
      CatalogScene(
        'Text at 200% · .unreachable with its age, Retry and Settings on a '
        '390pt phone',
        (_) => FaultBand.unreachable(
          serviceName: 'TrueNAS',
          since: const Duration(minutes: 6),
          onRetry: () {},
          onOpenSettings: () {},
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · .fault, a refused key: the remedy in the amber fill '
        'and Settings on a 390pt phone',
        (_) => FaultBand.fault(
          serviceName: 'Radarr',
          reason: ServiceFailureReason.unauthorized,
          onRetry: () {},
          onOpenSettings: () {},
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · .partial and .stale on a 390pt phone',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FaultBand.partial(
              message:
                  'Seerr returned 50 of 300 users; later pages are unavailable.',
              onRetry: () {},
            ),
            const SizedBox(height: 12),
            FaultBand.stale(
              age: const Duration(minutes: 6),
              detail: 'TrueNAS live metrics have not returned.',
              onRefresh: () {},
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
