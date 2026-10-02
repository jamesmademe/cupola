import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_copy.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
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

  /// Whether the sheet picks where the request goes: the server, the quality
  /// profile and the folder. Only the operator with an account that may
  /// choose (`SeerrAbility.chooseDestination`) does; everybody else sends
  /// the title alone and the server applies its own defaults, so the sheet
  /// reads none of Seerr's Radarr and Sonarr servers.
  final bool choosesDestination;

  /// Without [choosesDestination]: whether the request is for the 4K copy.
  final bool is4k;

  /// Without [choosesDestination], for a series: the seasons a request may
  /// ask for, in order. Empty for a movie, and while they are read.
  final List<int> seasons;

  /// The seasons ticked, of [seasons]. Asked for one by one only where the
  /// server takes partial requests; otherwise every season goes.
  final Set<int> selectedSeasons;

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
    this.choosesDestination = true,
    this.is4k = false,
    this.seasons = const [],
    this.selectedSeasons = const {},
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

  /// A profile is needed only by a sheet that picks one; without the
  /// pickers the server applies its own.
  bool get canSubmit =>
      (!choosesDestination || selectedProfileId != null) &&
      !isSubmitting &&
      !isLoading &&
      error == null;

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
    bool? choosesDestination,
    bool? is4k,
    List<int>? seasons,
    Set<int>? selectedSeasons,
  }) {
    return RequestFormState(
      choosesDestination: choosesDestination ?? this.choosesDestination,
      is4k: is4k ?? this.is4k,
      seasons: seasons ?? this.seasons,
      selectedSeasons: selectedSeasons ?? this.selectedSeasons,
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
///
/// The requester is told only that she was signed out, never which service.
String _loadFailure(Object error, {bool brief = false}) =>
    classifyConnectionFailure(error) == ServiceFailureReason.sessionEnded
    // Nothing to wait for: the person signs in again.
    ? brief
          ? '${Lexicon.youWereSignedOut}. ${Lexicon.signInToKeepAsking}'
          : '${describeFailureOf(ServiceKey.seerr, error).headline}, so the '
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
    // Who picks where the request goes is the gate's to say, and only the
    // operator with an account that may choose does. Everybody else sends the
    // title and nothing else, and the sheet never reads Seerr's servers:
    // they are the operator's, named "Radarr 4K".
    final chooses = ref
        .read(roleGateProvider(''))
        .operatorAction(SeerrAbility.chooseDestination)
        .acts;
    if (!chooses) {
      state = state.copyWith(
        choosesDestination: false,
        is4k: arg.copies == SeerrRequestCopies.uhd,
      );
      try {
        // Nothing to read, but a Seerr that signed out says so here, before
        // a request is filled in that cannot be sent.
        ref.read(seerrServiceProvider);
      } catch (error) {
        state = state.copyWith(
          isLoading: false,
          error: _loadFailure(error, brief: _brief),
          errorReason: classifyConnectionFailure(error),
        );
        return;
      }
      await _loadSeasons();
      return;
    }
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

  /// The seasons a request for a series may ask for: every season with
  /// episodes, less those the server holds or has been asked for already, as
  /// the detail page reads them. A page that did not load leaves every
  /// season to the server, which drops what it has.
  Future<void> _loadSeasons() async {
    var seasons = const <int>[];
    if (arg.mediaType == 'tv') {
      try {
        final details = await ref.read(
          discoverDetailProvider((id: arg.mediaId, type: 'tv')).future,
        );
        final numbering = await ref.read(seerrNumberingProvider.future);
        final all = [
          for (final raw in (details['seasons'] as List?) ?? const [])
            if (raw is Map<String, dynamic>) TvSeason.fromJson(raw),
        ];
        final requestable = [
          for (final season in all)
            if (season.seasonNumber > 0 && season.episodeCount > 0)
              season.seasonNumber,
        ];
        final missing = seerrRequestGate(
          details['mediaInfo'] as Map<String, dynamic>?,
          isMovie: false,
          seasons: all,
          numbering: numbering,
        ).missingSeasons;
        seasons = missing.isEmpty ? requestable : missing;
      } catch (_) {
        // The server drops every season it has: asking for all is safe.
      }
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      isLoading: false,
      seasons: seasons,
      selectedSeasons: seasons.toSet(),
      clearError: true,
    );
  }

  /// Without the pickers: the request is for the 4K copy, or the standard.
  void selectQuality({required bool is4k}) {
    state = state.copyWith(is4k: is4k);
  }

  /// Without the pickers: [season] ticked or not.
  void toggleSeason(int season) {
    final selected = {...state.selectedSeasons};
    if (!selected.remove(season)) selected.add(season);
    state = state.copyWith(selectedSeasons: selected);
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

  /// Sends the request, and says why not when it was not made: null on
  /// success.
  ///
  /// Without the pickers the request carries the title, the copy and, where
  /// the server takes partial requests ([partialRequests]), the seasons
  /// ticked; the server applies its own server, profile and folder.
  /// [title] names the title in the requester's words when it fails.
  Future<RequestSubmitFailure?> submitRequest({
    bool partialRequests = false,
    String? title,
  }) async {
    final chooses = state.choosesDestination;
    if (chooses && state.selectedProfileId == null) {
      return const RequestSubmitFailure('No profile selected');
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final service = ref.read(seerrServiceProvider);
      if (chooses) {
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
      } else {
        final ticked = state.selectedSeasons;
        await service.createRequest(
          mediaType: arg.mediaType,
          mediaId: arg.mediaId,
          is4k: state.is4k,
          seasons: partialRequests && ticked.length < state.seasons.length
              ? [
                  for (final season in state.seasons)
                    if (ticked.contains(season)) season,
                ]
              : null,
        );
      }
      return null;
    } catch (error) {
      return _submitFailure(error, title: title);
    } finally {
      if (ref.mounted) state = state.copyWith(isSubmitting: false);
    }
  }

  /// What a request Seerr did not make says: the server's own reason where
  /// it gave one, in the voice of who reads it.
  RequestSubmitFailure _submitFailure(Object error, {String? title}) {
    if (error is SeerrNothingRequested) {
      return const RequestSubmitFailure(Lexicon.noSeasonsLeft);
    }
    final gate = ref.read(roleGateProvider(''));
    final kind = arg.mediaType == 'movie'
        ? SeerrMediaKind.movie
        : SeerrMediaKind.tv;
    final brief = gate.faultVoice == FaultVoice.brief;
    final server = gate.server?.title ?? ServiceKey.seerr.title;
    // The key's refusals read as they always have; an account's are the
    // server's own reasons.
    final account = gate.grant?.isApiKey == false;
    switch (account ? seerrRefusalOf(error) : null) {
      case SeerrRefusal.alreadyRequested:
        return const RequestSubmitFailure(Lexicon.alreadyRequested);
      case SeerrRefusal.blocklisted:
        return const RequestSubmitFailure(Lexicon.blockedByOwner);
      case SeerrRefusal.quotaReached:
        // Read again, so the sheet dims Request with the limit as it stands.
        final id = _lensId();
        final held = id == null ? null : ref.read(seerrQuotaProvider(id)).value;
        if (id != null) ref.invalidate(seerrQuotaProvider(id));
        final quota = SeerrQuotaStatus(
          limit: held?.of(kind).limit,
          days: held?.of(kind).days,
          restricted: true,
        );
        return RequestSubmitFailure(
          brief
              ? RoleGateCopy.youQuotaReached(quota, kind)
              : RoleGateCopy.accountQuotaReached(quota, kind, server: server),
        );
      case SeerrRefusal.requestNotAllowed || SeerrRefusal.permissionDenied:
        // The transport read `/auth/me` again, so the gate says it as it is.
        return RequestSubmitFailure(
          gate.requestAction(kind).reason ??
              (brief
                  ? RoleGateCopy.youCannot(SeerrAbility.request, kind: kind)
                  : RoleGateCopy.accountCannot(
                      SeerrAbility.request,
                      server: server,
                      kind: kind,
                    )),
        );
      case _:
        break;
    }
    if (brief) {
      final reason = classifyConnectionFailure(error);
      if (reason == ServiceFailureReason.sessionEnded) {
        return const RequestSubmitFailure(
          '${Lexicon.youWereSignedOut}. ${Lexicon.signInToKeepAsking}',
        );
      }
      return RequestSubmitFailure(
        Lexicon.couldNotAskFor(title),
        retryHelps: failureRetryHelps(reason),
      );
    }
    return RequestSubmitFailure(
      'Could not send the request. '
      '${writeFailureReason(ServiceKey.seerr, error)}',
      error: error,
    );
  }

  bool get _brief =>
      ref.read(roleGateProvider('')).faultVoice == FaultVoice.brief;

  String? _lensId() => ref.read(activeInstanceProvider(ServiceKey.seerr))?.id;
}

/// Why a request was not made, as the sheet says it: [message], and whether
/// sending it again can still change the answer ([retryHelps]).
class RequestSubmitFailure {
  const RequestSubmitFailure(
    this.message, {
    this.retryHelps = false,
    this.error,
  });

  final String message;
  final bool retryHelps;

  /// The failure behind the operator's message, for the toast's cause; null
  /// where the words are all there is to say.
  final Object? error;

  @override
  String toString() => message;
}
