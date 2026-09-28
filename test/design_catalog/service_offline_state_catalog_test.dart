@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'ServiceOfflineState',
    scenes: [
      CatalogScene(
        'ServiceOfflineState(since:, onOpenSettings:) · a known first-failure '
        'age, Retry and Settings',
        (_) => ServiceOfflineState(
          serviceName: 'SABnzbd',
          accent: ServiceKey.sabnzbd.accent,
          since: const Duration(minutes: 40),
          onRetry: () {},
          onOpenSettings: () {},
        ),
        width: 320,
      ),
      CatalogScene(
        'ServiceOfflineState · no first-failure time known, span dropped — '
        'Retry only, no onOpenSettings',
        (_) => ServiceOfflineState(
          serviceName: 'Transmission',
          accent: ServiceKey.transmission.accent,
          onRetry: () {},
        ),
        width: 320,
      ),
    ],
  );
}
