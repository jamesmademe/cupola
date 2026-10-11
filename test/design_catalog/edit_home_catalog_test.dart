@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/edit_home_page.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

class _Audience extends ShellAudienceNotifier {
  _Audience(this.audience);

  final Audience audience;

  @override
  Audience build() => audience;
}

class _Layout extends HomeLayoutNotifier {
  _Layout(this.layout);

  final HomeLayout layout;

  @override
  HomeLayout build() => layout;
}

void main() {
  catalogCard(
    'EditHome',
    width: 840,
    overrides: () async => settingsScopeOverrides(),
    scenes: [
      CatalogScene(
        'EditHomePage · the operator\'s default: Needs you first with its '
        'handle and no switch, the modules in order with their handles and '
        'switches, Set up next at the foot, Reset dimmed',
        (_) => const EditHomePage(),
        width: 390,
        height: 860,
      ),
      CatalogScene(
        'Arranged · Requests moved up, Downloads switched off: its words '
        'dim, Reset lights',
        (_) => const EditHomePage(),
        width: 390,
        height: 860,
        overrides: [
          homeLayoutProvider.overrideWith(
            () => _Layout(
              HomeLayout.defaultFor(Audience.operator)
                  .moved(HomeModule.requests, -2)
                  .switched(HomeModule.downloads, on: false),
            ),
          ),
        ],
      ),
      CatalogScene(
        'The requester\'s · her own modules, nothing locked, the operator\'s '
        'default explained under Reset',
        (_) => const EditHomePage(),
        width: 390,
        height: 700,
        overrides: [
          shellAudienceProvider.overrideWith(
            () => _Audience(Audience.requester),
          ),
        ],
      ),
      CatalogScene(
        'Text at 200% · the rows grow, the handles and switches keep 44pt',
        (_) => const EditHomePage(),
        width: 390,
        height: 1700,
        textScale: catalogTextScale,
      ),
    ],
  );
}
