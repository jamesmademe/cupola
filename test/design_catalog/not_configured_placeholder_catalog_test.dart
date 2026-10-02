@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

void main() {
  catalogCard(
    'NotConfiguredPlaceholder',
    // A Seerr account that signed out: the one connection of the household's
    // Seerr, its session gone.
    overrides: () async => settingsScopeOverrides(
      customize: (_) => const SettingsModel(
        instances: [
          ServiceInstance(
            id: 'seerr',
            service: ServiceKey.seerr,
            url: 'http://nas.home.arpa:5055',
            account: SeerrAccountSignIn(
              kind: SeerrAccountKind.local,
              login: 'anna@home.arpa',
              userId: 2,
              displayName: 'Anna',
              permissions: 32,
            ),
          ),
        ],
      ),
    ),
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
      CatalogScene(
        'NotConfiguredPlaceholder.forService(seerr) · a Seerr account that '
        'signed out is set up: it reads Signed out of Seerr, blue, and Sign '
        'in again opens its own form, never Set up Seerr',
        (_) => NotConfiguredPlaceholder.forService(ServiceKey.seerr),
        width: 320,
      ),
    ],
  );
}
