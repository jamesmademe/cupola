import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/sonarr_monitor.dart';
import 'package:cupola/features/series/domain/sonarr_series_type.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One selectable option: a quality profile.
typedef ArrProfileOption = ({int id, String name});

/// Which connection the add sheet is filling in for.
///
/// The item itself is not part of the key: the sheet is modal, so only one is
/// ever open, and a `RadarrMovie` has no value equality — keying on it would
/// mint a fresh entry on every rebuild.
typedef ArrAddArgs = ({String instanceId, ServiceKey service});

class ArrAddFormState {
  final List<ArrProfileOption> profiles;
  final List<String> rootFolders;

  /// The free space under each root folder, in bytes, where the server said.
  final Map<String, int> freeSpace;

  /// How many indexers a search asks ([BaseArrService.countSearchingIndexers]),
  /// null when the server did not say.
  final int? searchingIndexers;

  final int? profileId;
  final String? rootFolder;
  final bool monitored;

  /// Sonarr only: which episodes it looks for, under [monitored].
  final SonarrMonitor sonarrMonitor;

  /// Sonarr only: how it numbers the episodes; null keeps the lookup's.
  final SonarrSeriesType? seriesType;

  final bool searchOnAdd;
  final bool isLoading;
  final bool isSubmitting;

  /// The sentence, in the user's register.
  final String? error;

  /// The diagnostic behind it, demoted to its own line. Same two-register shape
  /// `SnackBarHelper.error` and `AppErrorState` use.
  final String? errorDetail;

  /// Why the request failed, when one was sent — the tone of the sheet's
  /// glyph. Null for a fault that was an answer (Radarr has no quality
  /// profile) or a post this sheet refused to send: amber, never red.
  final ServiceFailureReason? errorReason;

  const ArrAddFormState({
    this.profiles = const [],
    this.rootFolders = const [],
    this.freeSpace = const {},
    this.searchingIndexers,
    this.profileId,
    this.rootFolder,
    this.monitored = true,
    this.sonarrMonitor = SonarrMonitor.all,
    this.seriesType,
    this.searchOnAdd = true,
    this.isLoading = true,
    this.isSubmitting = false,
    this.error,
    this.errorDetail,
    this.errorReason,
  });

  /// Whether the form can be posted.
  ///
  /// A load that failed leaves no selections, so this is false for the reason
  /// that matters: there is nothing honest to post.
  bool get canSubmit =>
      !isLoading && !isSubmitting && profileId != null && rootFolder != null;

  ArrAddFormState copyWith({
    List<ArrProfileOption>? profiles,
    List<String>? rootFolders,
    Map<String, int>? freeSpace,
    int? searchingIndexers,
    int? profileId,
    String? rootFolder,
    bool? monitored,
    SonarrMonitor? sonarrMonitor,
    SonarrSeriesType? seriesType,
    bool? searchOnAdd,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    String? errorDetail,
    ServiceFailureReason? errorReason,
    bool clearError = false,
  }) {
    return ArrAddFormState(
      profiles: profiles ?? this.profiles,
      rootFolders: rootFolders ?? this.rootFolders,
      freeSpace: freeSpace ?? this.freeSpace,
      searchingIndexers: searchingIndexers ?? this.searchingIndexers,
      profileId: profileId ?? this.profileId,
      rootFolder: rootFolder ?? this.rootFolder,
      monitored: monitored ?? this.monitored,
      sonarrMonitor: sonarrMonitor ?? this.sonarrMonitor,
      seriesType: seriesType ?? this.seriesType,
      searchOnAdd: searchOnAdd ?? this.searchOnAdd,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
      errorReason: clearError ? null : (errorReason ?? this.errorReason),
    );
  }
}

final arrAddFormProvider = NotifierProvider.autoDispose
    .family<ArrAddFormNotifier, ArrAddFormState, ArrAddArgs>(
      ArrAddFormNotifier.new,
    );

class ArrAddFormNotifier extends Notifier<ArrAddFormState> {
  ArrAddFormNotifier(this.arg);

  final ArrAddArgs arg;

  /// Whether this notifier is still attached to a live provider.
  ///
  /// Every message here is produced *after* an await — a profile fetch, an add
  /// — and the provider is `autoDispose` behind a modal sheet, so dismissing the
  /// sheet mid-request disposes it before the answer lands. Assigning `state`
  /// then throws `UnmountedRefException`, and in [_load] the `catch` that would
  /// have reported it opens with an assignment of its own, so the second throw
  /// escapes the microtask with nothing to catch it.
  bool _alive = true;

  /// What this connection is called in a sentence — `Radarr · Away`.
  ///
  /// Every message this notifier produces carries it. "The add failed" is
  /// useless on a screen where two Radarr are both visible, and the section
  /// heading the user tapped under is off-screen behind the sheet.
  ///
  /// Resolved once, in [build], rather than on each read: the reads happen after
  /// awaits, and `ref` is unusable once this is disposed. The sheet is modal and
  /// shows one connection, so there is nothing here that can change under it.
  String connectionName = '';

  @override
  ArrAddFormState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    connectionName = ref
        .read(currentSettingsProvider)
        .connectionTitle(arg.instanceId, arg.service);
    Future.microtask(_load);
    return const ArrAddFormState();
  }

  /// Publishes [next] unless the sheet is already gone. See [_alive].
  void _emit(ArrAddFormState next) {
    if (_alive) state = next;
  }

  Future<void> _load() async {
    if (!_alive) return;
    try {
      final options = await _fetchOptions();

      // An empty answer here is a real sentence about the server, not a
      // stand-in for a failed request: `fetchRootFolders` throws rather than
      // degrading, so an unreachable server never lands in this branch.
      final missing = switch (options) {
        _ when options.rootFolders.isEmpty => 'root folder',
        _ when options.profiles.isEmpty => 'quality profile',
        _ => null,
      };
      if (missing != null) {
        _emit(
          state.copyWith(
            isLoading: false,
            error: '$connectionName has no $missing configured.',
          ),
        );
        return;
      }

      _emit(
        state.copyWith(
          profiles: options.profiles,
          rootFolders: options.rootFolders,
          freeSpace: options.freeSpace,
          // The defaults that make the common case two taps: first profile,
          // first folder, monitored, and search for it now.
          profileId: options.profiles.first.id,
          rootFolder: options.rootFolders.first,
          isLoading: false,
          clearError: true,
        ),
      );
      // Read beside the form, never holding it: a figure the sheet can do
      // without.
      unawaited(_countIndexers());
    } catch (error) {
      // Classified, not "Couldn't reach" for everything: a refused key is an
      // answer, and the sheet said the server could not be reached.
      final reason = classifyConnectionFailure(error);
      _emit(
        state.copyWith(
          isLoading: false,
          error:
              '${describeFailureOf(arg.service, error, subject: connectionName).headline}.',
          errorDetail: failureDiagnostic(error),
          errorReason: reason,
        ),
      );
    }
  }

  Future<
    ({
      List<ArrProfileOption> profiles,
      List<String> rootFolders,
      Map<String, int> freeSpace,
    })
  >
  _fetchOptions() async {
    switch (arg.service) {
      case ServiceKey.radarr:
        final service = ref.read(radarrServiceForProvider(arg.instanceId));
        final (profiles, folders) = await (
          service.getQualityProfiles(),
          service.getRootFolders(),
        ).wait;
        return (
          profiles: _profiles(profiles),
          rootFolders: _paths(folders),
          freeSpace: _freeSpace(folders),
        );
      case ServiceKey.sonarr:
        final service = ref.read(sonarrServiceForProvider(arg.instanceId));
        final (profiles, folders) = await (
          service.getQualityProfiles(),
          service.getRootFolders(),
        ).wait;
        return (
          profiles: _profiles(profiles),
          rootFolders: _paths(folders),
          freeSpace: _freeSpace(folders),
        );
      // Named rather than defaulted. `ArrAddRequest` is sealed so that an arr
      // added later is a compile error instead of a plus over a sheet that
      // cannot post; a `default:` here handed that guarantee back, by quietly
      // fetching another arr's profiles for whatever key arrived.
      default:
        throw ArgumentError.value(
          arg.service,
          'service',
          'has no add form; only Radarr and Sonarr can be added to',
        );
    }
  }

  /// How many indexers a search on this server asks, once it says.
  Future<void> _countIndexers() async {
    final count = switch (arg.service) {
      ServiceKey.radarr =>
        ref
            .read(radarrServiceForProvider(arg.instanceId))
            .countSearchingIndexers(),
      ServiceKey.sonarr =>
        ref
            .read(sonarrServiceForProvider(arg.instanceId))
            .countSearchingIndexers(),
      _ => null,
    };
    final answer = await count;
    if (answer == null || !_alive) return;
    state = state.copyWith(searchingIndexers: answer);
  }

  void selectProfile(int id) =>
      state = state.copyWith(profileId: id, clearError: true);

  void selectRootFolder(String path) =>
      state = state.copyWith(rootFolder: path, clearError: true);

  void setMonitored(bool value) => state = state.copyWith(monitored: value);

  void setSearchOnAdd(bool value) => state = state.copyWith(searchOnAdd: value);

  /// Sonarr: which episodes it looks for. `None` is not monitoring, and
  /// Sonarr does not search for a series it does not monitor.
  void setSonarrMonitor(SonarrMonitor value) => state = state.copyWith(
    sonarrMonitor: value,
    monitored: value != SonarrMonitor.none,
    searchOnAdd: value != SonarrMonitor.none && state.searchOnAdd,
  );

  /// Sonarr: how it numbers the episodes.
  void setSeriesType(SonarrSeriesType value) =>
      state = state.copyWith(seriesType: value);

  /// Posts the add. Returns null on success, or the sentence to show.
  ///
  /// The failure is never swallowed: Radarr answers 400 for a title it already
  /// holds, and a caller that could not tell that from a success would report
  /// an add that never happened — the mistake `lookupItems` used to make, where
  /// "offline" and "no results" became one answer.
  Future<String?> submit(ArrAddRequest request) async {
    final profileId = state.profileId;
    final rootFolder = state.rootFolder;
    // A sentence, not null: null is this method's word for "it is on the
    // server now", and a caller that gets it back closes the sheet and marks
    // the row added. Refusing to post and reporting success is the same lie the
    // doc above says this method exists to prevent — `canSubmit` keeps the
    // button off, but the contract must hold without it.
    if (profileId == null || rootFolder == null) {
      return _refuse(request, 'the form is not filled in');
    }

    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      switch (request) {
        case RadarrAddRequest(:final movie):
          await ref
              .read(radarrServiceForProvider(request.instanceId))
              .addMovie(
                movie,
                qualityProfileId: profileId,
                rootFolderPath: rootFolder,
                monitored: state.monitored,
                searchForMovie: state.searchOnAdd,
              );
        case SonarrAddRequest(:final series):
          await ref
              .read(sonarrServiceForProvider(request.instanceId))
              .addSeries(
                series,
                qualityProfileId: profileId,
                rootFolderPath: rootFolder,
                monitored: state.monitored,
                searchForMissingEpisodes: state.searchOnAdd,
                monitor: state.sonarrMonitor,
                seriesType: state.seriesType?.wireValue,
              );
      }
      // Cleared on the way out as well as on the way in. This entry is keyed on
      // the connection, not on the item, and outlives the sheet by however long
      // `autoDispose` takes: leaving the flag set means the next row's sheet
      // opens with `canSubmit` false and a dead Add button.
      _emit(state.copyWith(isSubmitting: false));
      return null;
    } catch (error) {
      final message = "Could not add ${request.title} to $connectionName.";
      _emit(
        state.copyWith(
          isSubmitting: false,
          error: message,
          // The arr's own words when it gave any ("This movie has already
          // been added"), otherwise why in the classified words.
          errorDetail:
              failureServiceMessage(error) ??
              writeFailureReason(arg.service, error, subject: connectionName),
          errorReason: classifyConnectionFailure(error),
        ),
      );
      return message;
    }
  }

  /// Reports a post that was never attempted, in the same two registers a
  /// failed one uses, so the caller cannot mistake it for success.
  String _refuse(ArrAddRequest request, String detail) {
    final message = "Could not add ${request.title} to $connectionName.";
    _emit(
      state.copyWith(isSubmitting: false, error: message, errorDetail: detail),
    );
    return message;
  }
}

List<ArrProfileOption> _profiles(List<Map<String, dynamic>> raw) => [
  for (final entry in raw)
    if (entry['id'] is int)
      (id: entry['id'] as int, name: entry['name'] as String? ?? 'Profile'),
];

List<String> _paths(List<Map<String, dynamic>> raw) => [
  for (final entry in raw)
    if (entry['path'] is String && (entry['path'] as String).isNotEmpty)
      entry['path'] as String,
];

Map<String, int> _freeSpace(List<Map<String, dynamic>> raw) => {
  for (final entry in raw)
    if (entry['path'] case final String path when path.isNotEmpty)
      if (entry['freeSpace'] case final num space) path: space.toInt(),
};
