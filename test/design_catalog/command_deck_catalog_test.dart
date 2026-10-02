@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/command_deck_entry.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/command_deck.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import 'catalog.dart';

ServiceInstance _instance(
  ServiceKey service,
  String url, {
  String? id,
  String label = '',
}) => ServiceInstance(
  id: id ?? service.name,
  service: service,
  label: label,
  url: url,
  credential: 'k',
);

final _settings = SettingsModel(
  instances: [
    _instance(ServiceKey.seerr, 'https://requests.lan'),
    _instance(
      ServiceKey.radarr,
      'https://four-k.lan:7878',
      id: 'radarr',
      label: '4K',
    ),
    _instance(
      ServiceKey.radarr,
      'https://hd.lan:7879',
      id: 'radarr-hd11111',
      label: 'HD',
    ),
    _instance(ServiceKey.sonarr, 'https://sonarr.lan:8989'),
    _instance(ServiceKey.prowlarr, 'https://prowlarr.lan:9696'),
    _instance(ServiceKey.qbittorrent, 'https://qbit.lan:8080'),
  ],
);

/// Where the window has been, newest first. The first is where it stands,
/// which the deck leaves out.
const _recents = [
  '/dashboard',
  ServiceRoutes.radarrLibrary,
  '/activity',
  '/dashboard/sonarr/calendar',
  '/settings/certificates',
];

const _health = StackHealth(
  configured: 16,
  answering: 13,
  degraded: 0,
  unreachable: 3,
  checking: 0,
  notSetUp: 1,
);

class _FixedHealth extends StackHealthNotifier {
  @override
  StackHealth build() => _health;
}

late SharedPreferences _prefs;

/// The deck as the shell's overlay lays it out, with [query] typed into it.
///
/// Its own root container, since a nested `ProviderScope` would leave the
/// derived entry list reading the sheet's root. The query goes in through the
/// field's editing state, the way a keystroke does, so the deck filters.
class _OpenDeck extends StatefulWidget {
  const _OpenDeck({this.query = ''});

  final String query;

  @override
  State<_OpenDeck> createState() => _OpenDeckState();
}

class _OpenDeckState extends State<_OpenDeck> {
  late final _container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(_settings),
      initialOnboardingCompletedProvider.overrideWithValue(true),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      stackHealthProvider.overrideWith(_FixedHealth.new),
      recentLocationsProvider.overrideWith((ref) => _recents),
    ],
  );

  @override
  void initState() {
    super.initState();
    if (widget.query.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      EditableTextState? field;
      void visit(Element element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          field = element.state as EditableTextState;
          return;
        }
        element.visitChildElements(visit);
      }

      context.visitChildElements(visit);
      field?.userUpdateTextEditingValue(
        TextEditingValue(
          text: widget.query,
          selection: TextSelection.collapsed(offset: widget.query.length),
        ),
        SelectionChangedCause.keyboard,
      );
    });
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return UncontrolledProviderScope(
      container: _container,
      // The overlay from `desktop_shell.dart`: a 62% scrim, and the panel
      // centred at the top under a 760 × 520 cap.
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.62),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 520),
              child: FocusScope(
                autofocus: true,
                child: CommandDeck(onClose: () {}),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  /// The overlay spans right of the 56pt rail and below the 44pt chrome.
  const width = 1280.0 - 56;

  catalogCard(
    'CommandDeck',
    width: 1328,
    scenes: [
      const CatalogScene(
        'CommandDeck · empty query · the four sections, every connection in '
        'registry order, then recent places as trails; capped at 520, so it '
        'scrolls',
        _emptyQuery,
        width: width,
        height: 560,
        platform: CatalogPlatform.desktop,
      ),
      const CatalogScene(
        'CommandDeck · typed "radarr" · a match on label, detail and service '
        'title; the selected connection row keeps its glyph on AA',
        _radarr,
        width: width,
        height: 300,
        platform: CatalogPlatform.desktop,
      ),
      const CatalogScene(
        'CommandDeck · typed "cert" · a named Settings screen joins once you '
        'type',
        _cert,
        width: width,
        height: 230,
        platform: CatalogPlatform.desktop,
      ),
      const CatalogScene(
        'CommandDeck · nothing matched · one row offers the global search with '
        'the word, and the footer keeps teaching the keys',
        _nothing,
        width: width,
        height: 220,
        platform: CatalogPlatform.desktop,
      ),
      const CatalogScene(
        'Text at 200% · CommandDeck, empty query: the sections, the rows and '
        'the footer at twice the reading size',
        _emptyQuery,
        width: width,
        height: 760,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
      const CatalogScene(
        'Text at 200% · CommandDeck, typed "radarr"',
        _radarr,
        width: width,
        height: 460,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

Widget _emptyQuery(BuildContext _) => const _OpenDeck();
Widget _radarr(BuildContext _) => const _OpenDeck(query: 'radarr');
Widget _cert(BuildContext _) => const _OpenDeck(query: 'cert');
Widget _nothing(BuildContext _) => const _OpenDeck(query: 'metropolis');
