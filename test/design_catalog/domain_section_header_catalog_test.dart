@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/domain_section.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/service_connection_row.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

const _configured = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.qbittorrent,
  ServiceKey.sabnzbd,
  ServiceKey.jellyfin,
];

/// Every domain in `ServiceDomain` order, each with its members from
/// `ServiceKey.domain`.
Widget _allDomains(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final domain in ServiceDomain.values) ...[
        DomainSectionHeader(label: domain.label),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            domain.services.map((service) => service.title).join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    ],
  );
}

/// Settings › Connections: the header over its group card, with the page's
/// own inset around both, and no header for a domain with nothing configured.
Widget _connections(BuildContext context) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final domain in ServiceDomain.values)
        if (_configured.any((service) => service.domain == domain)) ...[
          DomainSectionHeader(
            label: domain.label,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
          ),
          SettingsGroupCard(
            children: [
              for (final service in _configured)
                if (service.domain == domain)
                  ServiceConnectionRow(service: service, onTap: () {}),
            ],
          ),
        ],
    ],
  ),
);

void main() {
  catalogCard(
    'DomainSectionHeader',
    width: 768,
    overrides: () async => [
      ...await settingsScopeOverrides(configured: _configured),
      serviceDiagnosisProvider.overrideWith(
        (ref, service) async =>
            const ServiceDiagnosis(ServiceConnectionStatus.connected),
      ),
    ],
    scenes: [
      CatalogScene(
        'DomainSectionHeader · default padding · the four domains in '
        'ServiceDomain order, members from ServiceKey.domain',
        _allDomains,
        width: 390,
      ),
      CatalogScene(
        'DomainSectionHeader(trailing:) · the label fills the row, the '
        'trailing widget sits at its end',
        (context) => DomainSectionHeader(
          label: 'Downloads',
          trailing: Text(
            '2 connected',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'Settings › Connections · padding 4 / 16 / 4 / 8 over a group card; '
        'Infrastructure has nothing configured, so it draws no header',
        _connections,
        width: 390,
      ),
      CatalogScene(
        'Settings › Connections on the desktop',
        _connections,
        width: 640,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · the four domains, a header with a trailing widget and '
        'Settings › Connections, at twice the reading size',
        (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _allDomains(context),
            DomainSectionHeader(
              label: 'Downloads',
              trailing: Text(
                '2 connected',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            _connections(context),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
