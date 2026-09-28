@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'NotConfiguredPlaceholder',
    scenes: [
      CatalogScene(
        'NotConfiguredPlaceholder.forService(radarr) · deep-links to '
        '/settings/service/radarr, for a service dashboard',
        (_) => NotConfiguredPlaceholder.forService(ServiceKey.radarr),
        width: 320,
      ),
      CatalogScene(
        'NotConfiguredPlaceholder(serviceName:) · the generic form, for a '
        'caller that only holds a name — lands on /settings',
        (_) => const NotConfiguredPlaceholder(serviceName: 'Bazarr'),
        width: 320,
      ),
    ],
  );
}
