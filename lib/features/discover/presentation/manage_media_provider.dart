import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';

import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

typedef ManageMediaArgs = ({
  Map<String, dynamic> mediaInfo,
  String mediaType,
  int tmdbId,
  int? tvdbId,
});

class ManageMediaState {
  final List<SeerrRequest> requests;
  final bool isLoading;
  final bool isDeleting;
  final String? error;

  const ManageMediaState({
    this.requests = const [],
    this.isLoading = true,
    this.isDeleting = false,
    this.error,
  });

  ManageMediaState copyWith({
    List<SeerrRequest>? requests,
    bool? isLoading,
    bool? isDeleting,
    String? error,
    bool clearError = false,
  }) {
    return ManageMediaState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      isDeleting: isDeleting ?? this.isDeleting,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The servers the lens's Seerr keeps [ServiceKey.radarr] or
/// [ServiceKey.sonarr] titles on, for the Manage sheet to bind each copy to
/// its server. Loading or failed reads as unknown, and the sheet then acts as
/// it did before it knew: never on a server it guessed.
final manageMediaServersProvider = FutureProvider.autoDispose
    .family<List<SeerrArrServer>, ServiceKey>((ref, arr) {
      return ref.watch(seerrServiceProvider).getArrServers(arr);
    }, retry: noProviderRetry);

final manageMediaProvider = NotifierProvider.autoDispose
    .family<ManageMediaNotifier, ManageMediaState, ManageMediaArgs>(
      ManageMediaNotifier.new,
    );

class ManageMediaNotifier extends Notifier<ManageMediaState> {
  ManageMediaNotifier(this.arg);

  final ManageMediaArgs arg;

  @override
  ManageMediaState build() {
    try {
      final requestsData = arg.mediaInfo['requests'] as List<dynamic>? ?? [];
      final requests = requestsData
          .map((request) {
            try {
              return SeerrRequest.fromJson(request as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<SeerrRequest>()
          .toList();

      return ManageMediaState(requests: requests, isLoading: false);
    } catch (_) {
      // Nothing was fetched here: the requests ride inside the media record
      // Seerr already sent, so a throw is a record nobody could read — an
      // answer, and amber, never "did not answer".
      return ManageMediaState(
        isLoading: false,
        error: sectionFailureMessage(
          ServiceKey.seerr,
          const FormatException(),
          consequence: 'the requests for this title are not shown',
        ),
      );
    }
  }

  int? get seerrMediaId => arg.mediaInfo['id'] as int?;

  /// Seerr's record carried no id, so there was nothing to address the write
  /// to and nothing was sent.
  static const _noMediaId =
      'Seerr sent this title without its id, so nothing was changed.';

  int? get externalServiceId => arg.mediaInfo['externalServiceId'] as int?;

  /// The arr this title's copies live in.
  ServiceKey get arr =>
      arg.mediaType == 'movie' ? ServiceKey.radarr : ServiceKey.sonarr;

  /// Every copy an arr holds for Seerr, the standard one first: read from
  /// `externalServiceId`/`serviceId` and `externalServiceId4k`/`serviceId4k`.
  /// It read `externalServiceId` alone, so a title only in 4K had no Media
  /// section, and a removal could only ever reach the standard copy.
  List<SeerrMediaCopy> get copies =>
      SeerrMediaCopy.fromMediaInfo(arg.mediaInfo);

  bool get hasExternalService => copies.isNotEmpty;

  /// [copies] bound to the servers Seerr keeps them on ([servers], null when
  /// they were not read) and to Cupola's connections to those servers.
  List<SeerrBoundCopy> boundCopies(List<SeerrArrServer>? servers) {
    final connections = ref
        .read(currentSettingsProvider)
        .configuredInstancesOf(arr);
    return [
      for (final copy in copies)
        SeerrBoundCopy.of(
          copy,
          arr: arr,
          servers: servers,
          connections: connections,
        ),
    ];
  }

  /// Whether the arr this item lives in is set up — through the registry's own
  /// check, not the flat first-instance projections (`radarrUrl`,
  /// `radarrApiKey`), which answered for one connection when the settings
  /// model can hold several.
  bool get isServiceConfigured {
    final settings = ref.read(currentSettingsProvider);
    return settings.isServiceConfigured(
      arg.mediaType == 'movie' ? ServiceKey.radarr : ServiceKey.sonarr,
    );
  }

  /// The Media section is drawn whenever the item is in an arr. It used to be
  /// hidden when that arr was not set up here, which hid the fact with it: the
  /// section's controls are cross-service jumps, drawn dimmed but tappable,
  /// and their toast leads to the settings that would make them work.
  bool get showMediaSection => hasExternalService;

  Future<String?> deleteRequest(int requestId) async {
    try {
      final service = ref.read(seerrServiceProvider);
      await service.deleteRequest(requestId);
      state = state.copyWith(
        requests: state.requests
            .where((request) => request.id != requestId)
            .toList(),
      );
      return null;
    } catch (error) {
      return 'Could not delete the request. '
          '${writeFailureReason(ServiceKey.seerr, error)}';
    }
  }

  /// Has Seerr remove one copy, the 4K one when [is4k]: from the server that
  /// holds it, with its files.
  Future<String?> removeFromService({bool is4k = false}) async {
    final mediaId = seerrMediaId;
    if (mediaId == null) {
      return _noMediaId;
    }

    state = state.copyWith(isDeleting: true);
    try {
      final service = ref.read(seerrServiceProvider);
      await service.deleteMediaFile(mediaId, is4k: is4k);
      return null;
    } catch (error) {
      return 'Could not remove this title. '
          '${writeFailureReason(ServiceKey.seerr, error)}';
    } finally {
      state = state.copyWith(isDeleting: false);
    }
  }

  Future<String?> clearAllData() async {
    final mediaId = seerrMediaId;
    if (mediaId == null) {
      return _noMediaId;
    }

    state = state.copyWith(isDeleting: true);
    try {
      final service = ref.read(seerrServiceProvider);
      await service.deleteMedia(mediaId);
      return null;
    } catch (error) {
      return 'Could not clear the data. '
          '${writeFailureReason(ServiceKey.seerr, error)}';
    } finally {
      state = state.copyWith(isDeleting: false);
    }
  }
}
