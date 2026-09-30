import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
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

  bool get hasExternalService => externalServiceId != null;

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

  Future<String?> removeFromService() async {
    final mediaId = seerrMediaId;
    if (mediaId == null) {
      return _noMediaId;
    }

    state = state.copyWith(isDeleting: true);
    try {
      final service = ref.read(seerrServiceProvider);
      await service.deleteMediaFile(mediaId);
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
