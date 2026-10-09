@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/presentation/widgets/ready_to_watch_module.dart';
import 'package:cupola/features/home/presentation/widgets/your_requests_module.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/requests/presentation/widgets/requester_request_row.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// Friday 9 October, 20:30.
final _now = DateTime(2026, 10, 9, 20, 30);

String _at(Duration before) => _now.subtract(before).toUtc().toIso8601String();
String _ahead(Duration after) => _now.add(after).toUtc().toIso8601String();

/// One of Anna's requests, as her Seerr sends it with its title read.
SeerrRequest _request(
  int id,
  String title, {
  int status = 2,
  int? media,
  bool is4k = false,
  Duration asked = const Duration(days: 3),
  Duration? answered,
  Duration? added,
  double? progress,
  Duration eta = const Duration(minutes: 40),
  bool stuck = false,
  bool watch = false,
}) => SeerrRequest.fromJson({
  'id': id,
  'status': status,
  'type': 'movie',
  'is4k': is4k,
  'createdAt': _at(asked),
  if (answered != null) 'updatedAt': _at(answered),
  'media': {
    'id': id,
    'tmdbId': 900 + id,
    'mediaType': 'movie',
    'status': ?media,
    'title': title,
    'posterPath': CatalogArt.tmdbPoster,
    'backdropPath': CatalogArt.tmdbBackdrop,
    'voteAverage': 7.1,
    'voteCount': 812,
    if (progress != null)
      'downloadStatus': [
        {
          'size': 1000,
          'sizeLeft': ((1 - progress) * 1000).round(),
          'status': stuck ? 'warning' : 'downloading',
          'estimatedCompletionTime': _ahead(eta),
        },
      ],
    if (watch) 'mediaUrl': 'https://watch.example/web/#/details?id=$id',
    if (added != null) 'mediaAddedAt': _at(added),
  },
}, numbering: SeerrNumbering.seerr);

final _charge = _request(
  1,
  'Charge',
  status: 1,
  asked: const Duration(minutes: 1),
);
final _sprite = _request(
  2,
  'Sprite Fright',
  media: 3,
  progress: 0.62,
  asked: const Duration(days: 2),
);
final _cosmos = _request(
  3,
  'Cosmos Laundromat',
  media: 3,
  progress: 0.4,
  stuck: true,
  asked: const Duration(days: 4),
);
final _coffee = _request(
  4,
  'Coffee Run',
  media: 5,
  added: const Duration(hours: 1, minutes: 50),
  asked: const Duration(days: 5),
  watch: true,
);
final _tears = _request(
  5,
  'Tears of Steel',
  media: 5,
  added: const Duration(days: 27),
  asked: const Duration(days: 30),
  watch: true,
);
final _metropolis = _request(
  6,
  'Metropolis',
  status: 3,
  answered: const Duration(days: 1),
);
final _spring = _request(
  7,
  'Spring',
  status: 4,
  asked: const Duration(days: 6),
);

MyRequest _mine(SeerrRequest request, {bool stale = false}) =>
    myRequestOf(request, now: _now, stale: stale);

final _anna = [_charge, _sprite, _cosmos, _coffee, _tears, _metropolis];

final _gate = roleGateProvider('').overrideWithValue(
  RoleGate(
    audience: Audience.requester,
    // REQUEST: she asks, and takes back her own while it waits.
    grant: const SeerrGrant.account(permissions: 32),
    server: SeerrServerFacts.fromPublicSettings({
      'mediaServerType': 2,
      'localLogin': true,
    }),
  ),
);

List<Override> _her(List<SeerrRequest> requests) => [
  requestsProvider.overrideWith((ref) async => requests),
  calendarClockProvider.overrideWithValue(() => _now),
  _gate,
];

/// The rows on a slab, as the Home's module and her page set them.
class _Slab extends StatelessWidget {
  const _Slab({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: room.slab,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: room.hair),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: children),
        ),
      ),
    );
  }
}

void main() {
  catalogCard(
    'RequesterRequestRow',
    width: 840,
    overrides: () async =>
        settingsScopeOverrides(configured: const [ServiceKey.seerr]),
    scenes: [
      CatalogScene(
        'RequesterRequestRow.home · the state at the row\'s end: the figure '
        'while it downloads, blue; waiting, blue; an answer, neutral',
        (_) => _Slab(
          children: [
            for (final (index, request) in [
              _sprite,
              _cosmos,
              _charge,
              _metropolis,
            ].indexed)
              RequesterRequestRow.home(
                mine: _mine(request),
                now: _now,
                divided: index > 0,
                onTap: () {},
              ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'RequesterRequestRow.page · the state under the title with its dot, '
        'Watch on what is on the server, never amber',
        (_) => _Slab(
          children: [
            for (final (index, request) in [
              _sprite,
              _cosmos,
              _coffee,
              _metropolis,
              _spring,
              _tears,
            ].indexed)
              RequesterRequestRow.page(
                mine: _mine(request),
                now: _now,
                divided: index > 0,
                onTap: () {},
                onWatch: _mine(request).watchAt == null ? null : () {},
              ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'RequesterWaitingCard · the one that waits: asked, approval, ready '
        'to watch, and Cancel request',
        (_) => Padding(
          padding: const EdgeInsets.all(16),
          child: RequesterWaitingCard(
            mine: _mine(_charge),
            now: _now,
            onTap: () {},
            cancel: OutlinedButton(
              onPressed: () {},
              child: const Text('Cancel request'),
            ),
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'The server went quiet · the rows stay as last read, the download '
        'no longer claims a figure',
        (_) => _Slab(
          children: [
            for (final (index, request) in [_sprite, _charge].indexed)
              RequesterRequestRow.page(
                mine: _mine(request, stale: true),
                now: _now,
                divided: index > 0,
                onTap: () {},
              ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'RequestsScreen · how many are ready and coming, the card that '
        'waits, then the rest',
        (_) => const RequestsScreen(),
        width: 390,
        height: 1500,
        overrides: [..._her(_anna)],
      ),
      CatalogScene(
        'RequestsScreen · nothing asked yet',
        (_) => const RequestsScreen(),
        width: 390,
        height: 500,
        overrides: [..._her(const [])],
      ),
      CatalogScene(
        'RequestsScreen · the server does not answer: one line and Retry',
        (_) => const RequestsScreen(),
        width: 390,
        height: 400,
        overrides: [
          requestsProvider.overrideWith(
            (ref) async =>
                throw const ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
          calendarClockProvider.overrideWithValue(() => _now),
          _gate,
        ],
      ),
      CatalogScene(
        'Ready to watch · the requester\'s Featured: the newest arrival, '
        'Watch on Jellyfin, and the second one line under it',
        (_) => const HomeReadyToWatchModule(),
        width: 390,
        overrides: [
          ..._her([
            _coffee,
            _request(
              8,
              'Sintel',
              media: 5,
              added: const Duration(days: 2),
              watch: true,
            ),
          ]),
        ],
      ),
      CatalogScene(
        'Your requests · what moves first, then what waits, and the way to '
        'all of them',
        (_) => const HomeYourRequestsModule(),
        width: 390,
        overrides: [..._her(_anna)],
      ),
      CatalogScene(
        'Your requests · nothing on its way: a calm line, and Discover',
        (_) => const HomeYourRequestsModule(),
        width: 390,
        overrides: [
          ..._her([_tears]),
        ],
      ),
      CatalogScene(
        'Text at 200% · the rows, the card and Ready to watch',
        (_) => Column(
          children: [
            _Slab(
              children: [
                RequesterRequestRow.home(
                  mine: _mine(_sprite),
                  now: _now,
                  onTap: () {},
                ),
                RequesterRequestRow.page(
                  mine: _mine(_coffee),
                  now: _now,
                  divided: true,
                  onTap: () {},
                  onWatch: () {},
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: RequesterWaitingCard(
                mine: _mine(_charge),
                now: _now,
                onTap: () {},
                cancel: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Cancel request'),
                ),
              ),
            ),
            const HomeReadyToWatchModule(),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
        overrides: [
          ..._her([_coffee]),
        ],
      ),
    ],
  );
}
