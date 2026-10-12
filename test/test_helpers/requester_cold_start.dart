import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_download.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart'
    show seerrNumberingProvider;
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'settings_scope.dart';

/// 20:53 on Monday 12 October 2026: the moment the requester's Home last drew,
/// in the cold-start tests.
final requesterNow = DateTime(2026, 10, 12, 20, 53);

/// One of her requests, as Seerr's list gives it. Times are given as ages
/// before [requesterNow]. No artwork: a picture would load for ever in a test.
SeerrRequest requesterRequest({
  int id = 1,
  String title = 'Sintel',
  int tmdbId = 45,
  RequestStatus status = RequestStatus.completed,
  SeerrMediaAvailability availability = SeerrMediaAvailability.available,
  Duration asked = const Duration(days: 5),
  Duration? answered,
  Duration? arrived = const Duration(days: 2),
  String? watchUrl,
  List<SeerrDownload> downloads = const [],
  RequestedBy? requestedBy,
  bool is4k = false,
  String type = 'movie',
  double? voteAverage,
}) {
  DateTime ago(Duration age) => requesterNow.subtract(age);
  return SeerrRequest(
    id: id,
    status: status,
    createdAt: ago(asked).toUtc().toIso8601String(),
    updatedAt: answered == null
        ? null
        : ago(answered).toUtc().toIso8601String(),
    type: type,
    is4k: is4k,
    requestedBy: requestedBy,
    media: RequestMedia(
      title: title,
      tmdbId: tmdbId,
      status: is4k ? SeerrMediaAvailability.unknown : availability,
      status4k: is4k ? availability : SeerrMediaAvailability.unknown,
      mediaUrl: is4k ? null : watchUrl,
      mediaUrl4k: is4k ? watchUrl : null,
      addedAt: arrived == null ? null : ago(arrived),
      downloads: is4k ? const [] : downloads,
      downloads4k: is4k ? downloads : const [],
      voteAverage: voteAverage,
      voteCount: voteAverage == null ? null : 1000,
    ),
  );
}

/// A download Seerr follows that is moving: 62%, ending at [finishesAt].
SeerrDownload movingDownload(DateTime finishesAt) => SeerrDownload(
  size: 1000,
  sizeLeft: 380,
  state: SeerrDownloadState.downloading,
  finishesAt: finishesAt,
);

/// A Seerr connection signed in as the account [userId]: no key, a session.
SettingsModel seerrSignedInAs(SettingsModel settings, {int userId = 7}) {
  final instance = settings.instancesOf(ServiceKey.seerr).first;
  return settings.copyWithInstance(
    instance.copyWith(
      credential: '',
      account: SeerrAccountSignIn(
        kind: SeerrAccountKind.local,
        login: 'anna@example.com',
        userId: userId,
        displayName: 'Anna',
        session: 'session',
        permissions: 32,
      ),
    ),
  );
}

/// The requester's Home at a cold start: one run of the app over a shared
/// [store], as a start over the same file would be.
///
/// Every run is a fresh scope over the same store, so the first run draws and
/// keeps what its Seerr answers, and the second starts with only what was
/// kept: its live reads are whatever its caller says (a `Completer` that never
/// completes, or a failure).
class RequesterColdStart {
  RequesterColdStart() : store = LastKnownStore.memory();

  final LastKnownStore store;

  /// Pumps [child] for her, signed in to Seerr as [userId], with [requests],
  /// [trending] and [comingSoon] as the live reads.
  Future<void> run(
    WidgetTester tester, {
    required Widget child,
    Future<List<SeerrRequest>> Function()? requests,
    Future<List<MediaPreview>> Function()? trending,
    Future<List<MediaPreview>> Function()? comingSoon,
    SettingsModel Function(SettingsModel)? customize,
    List<Override> overrides = const [],
    int userId = 7,
    DateTime? now,
  }) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = now ?? requesterNow;
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.seerr],
            customize: (settings) {
              final signedIn = seerrSignedInAs(settings, userId: userId);
              return customize?.call(signedIn) ?? signedIn;
            },
          ),
          audienceProvider.overrideWithValue(Audience.requester),
          // Her account's server facts are a network read of their own.
          roleGateProvider.overrideWith(
            (ref, id) => const RoleGate(audience: Audience.requester),
          ),
          lastKnownStoreProvider.overrideWithValue(store),
          calendarClockProvider.overrideWithValue(() => clock),
          featuredAdvancesProvider.overrideWithValue(false),
          // The poster's badge reads the server's numbering, a read of its own.
          seerrNumberingProvider.overrideWith((ref) async => null),
          homeLivePollProvider.overrideWith((ref) {}),
          homeRecoveryPollProvider.overrideWith((ref) {}),
          requestsProvider.overrideWith(
            (ref) => requests?.call() ?? Completer<List<SeerrRequest>>().future,
          ),
          atriumTrendingProvider.overrideWith(
            (ref) => trending?.call() ?? Completer<List<MediaPreview>>().future,
          ),
          comingSoonProvider.overrideWith(
            (ref) =>
                comingSoon?.call() ?? Completer<List<MediaPreview>>().future,
          ),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [const HomeAsOfLine(), child]),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }
}
