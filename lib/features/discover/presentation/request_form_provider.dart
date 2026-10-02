import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const Object _noSelectionUpdate = Object();

/// The title a request is for, and which of its copies may be asked for
/// ([SeerrRequestCopies], from the request gate): the sheet lists the servers
/// of those copies only, and opens on the 4K one when only the 4K copy is
/// open.
typedef RequestFormArgs = ({
  int mediaId,
  String mediaType,
  SeerrRequestCopies copies,
});

class SeerrServer {
  final int id;
  final String name;
  final int? activeProfileId;
  final String? activeDirectory;

  /// The server takes 4K requests. Seerr keeps a 4K copy of a title apart from
  /// its standard one, and a request is one or the other: it is the server
  /// that decides which, so a request sent here says `is4k`.
  final bool is4k;

  /// The server Seerr sends a request of its resolution to when the request
  /// names none.
  final bool isDefault;

  const SeerrServer({
    required this.id,
    required this.name,
    this.activeProfileId,
    this.activeDirectory,
    this.is4k = false,
    this.isDefault = false,
  });

  factory SeerrServer.fromJson(Map<String, dynamic> json) {
    return SeerrServer(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Server',
      activeProfileId: json['activeProfileId'] as int?,
      activeDirectory: json['activeDirectory'] as String?,
      is4k: json['is4k'] == true,
      isDefault: json['isDefault'] == true,
    );
  }

  /// The server's name as the sheet lists it: Seerr's own, with `· 4K` after
  /// it when the server takes 4K requests and its name does not already say
  /// so. Picking a 4K server makes the request a 4K one, and the list is the
  /// only place that says which servers those are.
  String get choiceLabel {
    if (!is4k || name.toLowerCase().contains('4k')) return name;
    return '$name · 4K';
  }
}

/// The server a request goes to when the person asking chose none: the
/// default standard server, as Seerr itself would pick it.
///
/// Seerr marks one default per resolution (`isDefault` with `is4k`), and the
/// sheet used to take whichever server it listed first, which could be the 4K
/// one, and then send the request without `is4k`: a standard request filed on
/// a 4K server. A 4K copy is a choice the person makes by picking a 4K
/// server, never the sheet's default while a standard server exists.
///
/// [is4k] when only the 4K copy may be asked for: the default 4K server, as
/// Seerr would pick it for a 4K request.
SeerrServer? defaultRequestServer(
  List<SeerrServer> servers, {
  bool is4k = false,
}) {
  return servers.where((s) => s.isDefault && s.is4k == is4k).firstOrNull ??
      servers.where((s) => s.is4k == is4k).firstOrNull ??
      servers.where((s) => s.isDefault).firstOrNull ??
      servers.firstOrNull;
}

/// The servers the sheet offers for [copies]: those that take a copy a
/// request may be for. A 4K server is not offered while the 4K copy is on
/// disk or asked for already, nor a standard one while the standard copy
/// is; Seerr would refuse the request. When the filter would leave nothing,
/// every server is offered, as the sheet always did.
List<SeerrServer> requestServersFor(
  List<SeerrServer> servers,
  SeerrRequestCopies copies,
) {
  final offered = switch (copies) {
    SeerrRequestCopies.standard => [
      for (final server in servers)
        if (!server.is4k) server,
    ],
    SeerrRequestCopies.uhd => [
      for (final server in servers)
        if (server.is4k) server,
    ],
    SeerrRequestCopies.both || SeerrRequestCopies.none => servers,
  };
  return offered.isEmpty ? servers : offered;
}

class QualityProfileOption {
  final int id;
  final String name;

  const QualityProfileOption({required this.id, required this.name});

  factory QualityProfileOption.fromJson(Map<String, dynamic> json) {
    return QualityProfileOption(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? 'Profile',
    );
  }
}

class RootFolderOption {
  final String path;

  const RootFolderOption({required this.path});

  factory RootFolderOption.fromJson(Map<String, dynamic> json) {
    return RootFolderOption(path: json['path'] as String? ?? '');
  }
}

class RequestFormState {
  final List<SeerrServer> servers;
  final List<QualityProfileOption> profiles;
  final List<RootFolderOption> rootFolders;
  final int? selectedServerId;
  final int? selectedProfileId;
  final String? selectedRootFolder;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  /// Why [error] happened, when it was a read that failed; null when Seerr
  /// answered and the answer is the problem (it has no server to send to).
  ///
  /// The two used to be one red line: "No Radarr servers configured in Seerr"
  /// for a Seerr that had not answered at all. The sheet paints red only when
  /// this says nothing answered.
  final ServiceFailureReason? errorReason;

  const RequestFormState({
    this.servers = const [],
    this.profiles = const [],
    this.rootFolders = const [],
    this.selectedServerId,
    this.selectedProfileId,
    this.selectedRootFolder,
    this.isLoading = true,
    this.isSubmitting = false,
    this.error,
    this.errorReason,
  });

  /// Nothing answered: the one case the sheet paints red.
  bool get errorDidNotAnswer {
    final reason = errorReason;
    return reason != null && failureDidNotAnswer(reason);
  }

  /// The server the request will be sent to, when one is chosen.
  SeerrServer? get selectedServer {
    final id = selectedServerId;
    if (id == null) return null;
    return servers.where((server) => server.id == id).firstOrNull;
  }

  bool get canSubmit =>
      selectedProfileId != null && !isSubmitting && !isLoading && error == null;

  RequestFormState copyWith({
    List<SeerrServer>? servers,
    List<QualityProfileOption>? profiles,
    List<RootFolderOption>? rootFolders,
    Object? selectedServerId = _noSelectionUpdate,
    Object? selectedProfileId = _noSelectionUpdate,
    Object? selectedRootFolder = _noSelectionUpdate,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    ServiceFailureReason? errorReason,
    bool clearError = false,
  }) {
    return RequestFormState(
      servers: servers ?? this.servers,
      profiles: profiles ?? this.profiles,
      rootFolders: rootFolders ?? this.rootFolders,
      selectedServerId: identical(selectedServerId, _noSelectionUpdate)
          ? this.selectedServerId
          : selectedServerId as int?,
      selectedProfileId: identical(selectedProfileId, _noSelectionUpdate)
          ? this.selectedProfileId
          : selectedProfileId as int?,
      selectedRootFolder: identical(selectedRootFolder, _noSelectionUpdate)
          ? this.selectedRootFolder
          : selectedRootFolder as String?,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      // A new error brings its own reason (null when Seerr answered); an
      // update that leaves the error alone leaves its reason alone too.
      errorReason: clearError
          ? null
          : (error != null ? errorReason : this.errorReason),
    );
  }
}

/// A failed read of the request sheet's lists, as the sheet says it: the
/// classified headline, never the exception.
String _loadFailure(Object error) =>
    classifyConnectionFailure(error) == ServiceFailureReason.sessionEnded
    // Nothing to wait for: the person signs in again.
    ? '${describeFailureOf(ServiceKey.seerr, error).headline}, so the '
          'request cannot be sent.'
    : '${describeFailureOf(ServiceKey.seerr, error).headline}. '
          'The request cannot be sent until it does.';

final requestFormProvider = NotifierProvider.autoDispose
    .family<RequestFormNotifier, RequestFormState, RequestFormArgs>(
      RequestFormNotifier.new,
    );

class RequestFormNotifier extends Notifier<RequestFormState> {
  RequestFormNotifier(this.arg);

  final RequestFormArgs arg;

  @override
  RequestFormState build() {
    Future.microtask(_loadServers);
    return const RequestFormState();
  }

  /// Every `await` below is followed by a [Ref.mounted] check: the sheet can
  /// close while Seerr is still answering, and the form it was filling is gone
  /// by then. Writing `state` to it throws, from a microtask nobody awaits.
  Future<void> _loadServers() async {
    if (!ref.mounted) return;
    try {
      final service = ref.read(seerrServiceProvider);
      final serverMaps = arg.mediaType == 'movie'
          ? await service.getRadarrServers()
          : await service.getSonarrServers();
      if (!ref.mounted) return;
      final servers = requestServersFor(
        serverMaps.map(SeerrServer.fromJson).toList(),
        arg.copies,
      );

      if (servers.isEmpty) {
        // Seerr answered, with no server to send to: a fault with its
        // remedy, amber — never the red of a Seerr that did not answer,
        // which is what this line used to claim when the read had failed.
        final arr = arg.mediaType == 'movie' ? 'Radarr' : 'Sonarr';
        state = state.copyWith(
          isLoading: false,
          error:
              'Seerr answered, but it has no $arr server set up, so a '
              "request has nowhere to go. Add one in Seerr's settings.",
          clearError: false,
        );
        return;
      }

      final chosen = defaultRequestServer(
        servers,
        is4k: arg.copies == SeerrRequestCopies.uhd,
      )!;
      state = state.copyWith(
        servers: servers,
        selectedServerId: chosen.id,
        clearError: true,
      );
      await _loadProfiles(chosen.id);
    } catch (error) {
      if (!ref.mounted) return;
      // Classified, and never the exception: the sheet used to print
      // "Failed to load servers: DioException […]".
      state = state.copyWith(
        isLoading: false,
        error: _loadFailure(error),
        errorReason: classifyConnectionFailure(error),
      );
    }
  }

  Future<void> _loadProfiles(int serverId) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(seerrServiceProvider);
      final data = arg.mediaType == 'movie'
          ? await service.getRadarrProfiles(serverId)
          : await service.getSonarrProfiles(serverId);
      if (!ref.mounted) return;

      final profileMaps = data['profiles'] as List<dynamic>? ?? const [];
      final rootFolderMaps = data['rootFolders'] as List<dynamic>? ?? const [];
      final profiles = profileMaps
          .whereType<Map<String, dynamic>>()
          .map(QualityProfileOption.fromJson)
          .toList();
      final rootFolders = rootFolderMaps
          .whereType<Map<String, dynamic>>()
          .map(RootFolderOption.fromJson)
          .toList();

      final selectedServer = state.servers.firstWhere(
        (server) => server.id == serverId,
        orElse: () => const SeerrServer(id: 0, name: 'Server'),
      );

      final activeProfileId = selectedServer.activeProfileId;
      final activeDirectory = selectedServer.activeDirectory;

      final selectedProfileId =
          activeProfileId != null &&
              profiles.any((profile) => profile.id == activeProfileId)
          ? activeProfileId
          : profiles.isNotEmpty
          ? profiles.first.id
          : null;

      final selectedRootFolder =
          activeDirectory != null &&
              rootFolders.any((folder) => folder.path == activeDirectory)
          ? activeDirectory
          : rootFolders.isNotEmpty
          ? rootFolders.first.path
          : null;

      state = state.copyWith(
        profiles: profiles,
        rootFolders: rootFolders,
        selectedProfileId: selectedProfileId,
        selectedRootFolder: selectedRootFolder,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: _loadFailure(error),
        errorReason: classifyConnectionFailure(error),
      );
    }
  }

  /// Reads Seerr's servers again, after its connection changed: signed in
  /// again, say.
  void reload() {
    state = const RequestFormState();
    unawaited(_loadServers());
  }

  void selectServer(int serverId) {
    state = state.copyWith(selectedServerId: serverId, clearError: true);
    _loadProfiles(serverId);
  }

  void selectProfile(int profileId) {
    state = state.copyWith(selectedProfileId: profileId, clearError: true);
  }

  void selectRootFolder(String path) {
    state = state.copyWith(selectedRootFolder: path, clearError: true);
  }

  Future<String?> submitRequest() async {
    if (state.selectedProfileId == null) {
      return 'No profile selected';
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final service = ref.read(seerrServiceProvider);
      await service.createRequest(
        mediaType: arg.mediaType,
        mediaId: arg.mediaId,
        profileId: state.selectedProfileId,
        rootFolder: state.selectedRootFolder,
        serverId: state.selectedServerId,
        // The chosen server decides the copy: without it a request filed on
        // the 4K server was a standard request, tracked on the HD copy.
        is4k: state.selectedServer?.is4k ?? false,
      );
      return null;
    } catch (error) {
      return 'Could not send the request. '
          '${writeFailureReason(ServiceKey.seerr, error)}';
    } finally {
      if (ref.mounted) state = state.copyWith(isSubmitting: false);
    }
  }
}
