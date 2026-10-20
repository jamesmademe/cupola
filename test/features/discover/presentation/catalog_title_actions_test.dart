import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/catalog_title_actions.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/model_builders.dart';
import '../../../test_helpers/settings_scope.dart';

const _charge = MediaPreview(id: 811631, title: 'Charge', mediaType: 'movie');

const _available = MediaPreview(
  id: 811631,
  title: 'Charge',
  mediaType: 'movie',
  mediaInfo: {'status': 5},
);

class _AddsVia extends OperatorAddsViaNotifier {
  _AddsVia(this.value);
  final OperatorAddsVia value;
  @override
  OperatorAddsVia build() => value;
}

/// The labels the menu offers [media], with [overrides] for the viewer.
Future<List<String>> _labels(
  WidgetTester tester,
  MediaPreview media,
  List<Override> overrides,
) async {
  late WidgetRef captured;
  late BuildContext context;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        seerrNumberingProvider.overrideWith((ref) async => null),
        ...overrides,
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (c, ref, _) {
            captured = ref;
            context = c;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  final actions = await tester.runAsync(
    () => catalogTitleActions(
      context,
      captured,
      media,
      mediaType: media.mediaType,
      onOpen: () {},
    ),
  );
  return [for (final action in actions!) action.label];
}

final _requester = [
  currentSettingsProvider.overrideWith(
    (ref) => settingsWithServices(const [ServiceKey.seerr]),
  ),
  audienceProvider.overrideWithValue(Audience.requester),
  roleGateProvider('').overrideWithValue(
    const RoleGate(
      audience: Audience.requester,
      grant: SeerrGrant.account(permissions: 32),
    ),
  ),
];

List<Override> _operator({
  required List<int> held,
  OperatorAddsVia via = OperatorAddsVia.arr,
  bool seerrSends = true,
  bool answers = true,
}) {
  final settings = settingsWithServices(const [
    ServiceKey.seerr,
    ServiceKey.radarr,
  ]);
  final radarr = settings.primaryOf(ServiceKey.radarr)!.id;
  return [
    currentSettingsProvider.overrideWith((ref) => settings),
    audienceProvider.overrideWithValue(Audience.operator),
    roleGateProvider('').overrideWithValue(
      const RoleGate(audience: Audience.operator, grant: SeerrGrant.apiKey()),
    ),
    operatorAddsViaProvider.overrideWith(() => _AddsVia(via)),
    seerrSendsToProvider.overrideWith((ref, arr) async => seerrSends),
    moviesForProvider(radarr).overrideWith(
      (ref) async => answers
          ? [for (final tmdb in held) buildMovie(id: 42, tmdbId: tmdb)]
          : throw StateError('Radarr did not answer'),
    ),
  ];
}

void main() {
  testWidgets('the requester: Open, Request, Copy TMDB link', (tester) async {
    expect(await _labels(tester, _charge, _requester), [
      'Open',
      'Request',
      'Copy TMDB link',
    ]);
  });

  testWidgets('a title that is there offers no Request', (tester) async {
    expect(await _labels(tester, _available, _requester), [
      'Open',
      'Copy TMDB link',
    ]);
  });

  testWidgets('the operator, the title in Radarr: Open in Radarr and no Add', (
    tester,
  ) async {
    final labels = await _labels(
      tester,
      _charge,
      _operator(held: [_charge.id]),
    );
    expect(labels, hasLength(3));
    expect(labels[1], startsWith('Open in '));
    expect(labels, isNot(contains(startsWith('Add'))));
  });

  testWidgets('the operator adding to the arr: Add to its Radarr', (
    tester,
  ) async {
    final labels = await _labels(tester, _charge, _operator(held: const []));
    expect(labels[1], startsWith('Add to '));
  });

  testWidgets('the operator through Seerr, which has a Radarr: Request', (
    tester,
  ) async {
    expect(
      await _labels(
        tester,
        _charge,
        _operator(held: const [], via: OperatorAddsVia.seerr),
      ),
      ['Open', 'Request', 'Copy TMDB link'],
    );
  });

  testWidgets('a library that does not answer: neither Add nor Open in', (
    tester,
  ) async {
    expect(
      await _labels(tester, _charge, _operator(held: const [], answers: false)),
      ['Open', 'Copy TMDB link'],
    );
  });

  test('the TMDB page of a movie and of a series', () {
    expect(
      tmdbPageOf(_charge, mediaType: 'movie'),
      'https://www.themoviedb.org/movie/811631',
    );
    expect(
      tmdbPageOf(_charge, mediaType: 'tv'),
      'https://www.themoviedb.org/tv/811631',
    );
  });
}
