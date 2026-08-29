import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One selectable option: a quality profile, or a metadata profile.
typedef ArrProfileOption = ({int id, String name});

/// Rows added in this session, keyed by [ArrAddRequest.libraryKey].
///
/// Why this rather than invalidating `globalSearchResultsProvider`: that
/// provider is the whole fan-out. Rebuilding it re-runs a lookup against every
/// configured connection — four legs at a time against somebody's home servers
/// — to change one boolean whose value we already hold, because the add's
/// response came back carrying the library id it was given. It is also
/// `autoDispose`, so the invalidation would be a cold rebuild rather than a
/// refresh.
///
/// Navigating to the new detail page was the other candidate and is a worse
/// answer for the same reason: the user asked to add a film, not to leave the
/// list of search results they were working through. This keeps them on it.
///
/// Kept for the life of the app rather than the life of one query. The claim it
/// makes — "this connection holds this title" — does not stop being true when
/// the query changes, and the set holds one short string per add.
final libraryAdditionsProvider =
    NotifierProvider<LibraryAdditions, Set<String>>(LibraryAdditions.new);

class LibraryAdditions extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void markAdded(String libraryKey) {
    state = {...state, libraryKey};
  }
}

/// Which connection the add sheet is filling in for.
///
/// The item itself is not part of the key: the sheet is modal, so only one is
/// ever open, and a `RadarrMovie` has no value equality — keying on it would
/// mint a fresh entry on every rebuild.
typedef ArrAddArgs = ({String instanceId, ServiceKey service});

class ArrAddFormState {
  final List<ArrProfileOption> profiles;
  final List<String> rootFolders;

  /// Lidarr only, and empty everywhere else — see
  /// [LidarrService.fetchMetadataProfiles].
  final List<ArrProfileOption> metadataProfiles;

  final int? profileId;
  final String? rootFolder;
  final int? metadataProfileId;
  final bool monitored;
  final bool searchOnAdd;
  final bool isLoading;
  final bool isSubmitting;

  /// The sentence, in the user's register.
  final String? error;

  /// The diagnostic behind it, demoted to its own line. Same two-register shape
  /// `SnackBarHelper.error` and `AppErrorState` use.
  final String? errorDetail;

  const ArrAddFormState({
    this.profiles = const [],
    this.rootFolders = const [],
    this.metadataProfiles = const [],
    this.profileId,
    this.rootFolder,
    this.metadataProfileId,
    this.monitored = true,
    this.searchOnAdd = true,
    this.isLoading = true,
    this.isSubmitting = false,
    this.error,
    this.errorDetail,
  });

  /// Whether the form can be posted.
  ///
  /// A load that failed leaves no selections, so this is false for the reason
  /// that matters: there is nothing honest to post.
  bool get canSubmit =>
      !isLoading &&
      !isSubmitting &&
      profileId != null &&
      rootFolder != null &&
      (metadataProfiles.isEmpty || metadataProfileId != null);

  ArrAddFormState copyWith({
    List<ArrProfileOption>? profiles,
    List<String>? rootFolders,
    List<ArrProfileOption>? metadataProfiles,
    int? profileId,
    String? rootFolder,
    int? metadataProfileId,
    bool? monitored,
    bool? searchOnAdd,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    String? errorDetail,
    bool clearError = false,
  }) {
    return ArrAddFormState(
      profiles: profiles ?? this.profiles,
      rootFolders: rootFolders ?? this.rootFolders,
      metadataProfiles: metadataProfiles ?? this.metadataProfiles,
      profileId: profileId ?? this.profileId,
      rootFolder: rootFolder ?? this.rootFolder,
      metadataProfileId: metadataProfileId ?? this.metadataProfileId,
      monitored: monitored ?? this.monitored,
      searchOnAdd: searchOnAdd ?? this.searchOnAdd,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
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

  @override
  ArrAddFormState build() {
    Future.microtask(_load);
    return const ArrAddFormState();
  }

  /// What this connection is called in a sentence — `Radarr · Away`.
  ///
  /// Every message this notifier produces carries it. "The add failed" is
  /// useless on a screen where two Radarr are both visible, and the section
  /// heading the user tapped under is off-screen behind the sheet.
  String get connectionName =>
      ref
          .read(currentSettingsProvider)
          .instanceById(arg.instanceId)
          ?.displayTitle ??
      arg.service.title;

  Future<void> _load() async {
    try {
      final options = await _fetchOptions();

      // An empty answer here is a real sentence about the server, not a
      // stand-in for a failed request: `fetchRootFolders` throws rather than
      // degrading, so an unreachable server never lands in this branch.
      final missing = switch (options) {
        _ when options.rootFolders.isEmpty => 'root folder',
        _ when options.profiles.isEmpty => 'quality profile',
        // Lidarr's extra axis is not optional: an add without one is rejected,
        // so a server that has none cannot be added to at all.
        _
            when arg.service == ServiceKey.lidarr &&
                options.metadataProfiles.isEmpty =>
          'metadata profile',
        _ => null,
      };
      if (missing != null) {
        state = state.copyWith(
          isLoading: false,
          error: '$connectionName has no $missing configured.',
        );
        return;
      }

      state = state.copyWith(
        profiles: options.profiles,
        rootFolders: options.rootFolders,
        metadataProfiles: options.metadataProfiles,
        // The defaults that make the common case two taps: first profile,
        // first folder, monitored, and search for it now.
        profileId: options.profiles.first.id,
        rootFolder: options.rootFolders.first,
        metadataProfileId: options.metadataProfiles.firstOrNull?.id,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: "Couldn't reach $connectionName.",
        errorDetail: '$error',
      );
    }
  }

  Future<
    ({
      List<ArrProfileOption> profiles,
      List<String> rootFolders,
      List<ArrProfileOption> metadataProfiles,
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
          metadataProfiles: const <ArrProfileOption>[],
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
          metadataProfiles: const <ArrProfileOption>[],
        );
      case ServiceKey.lidarr:
        final service = ref.read(lidarrServiceForProvider(arg.instanceId));
        final (profiles, folders, metadata) = await (
          service.getQualityProfiles(),
          service.getRootFolders(),
          service.fetchMetadataProfiles(),
        ).wait;
        return (
          profiles: _profiles(profiles),
          rootFolders: _paths(folders),
          metadataProfiles: _profiles(metadata),
        );
      // Named rather than defaulted. `ArrAddRequest` is sealed so that an arr
      // added later is a compile error instead of a plus over a sheet that
      // cannot post; a `default:` here handed that guarantee back, by quietly
      // fetching Lidarr's profiles for whatever key arrived.
      default:
        throw ArgumentError.value(
          arg.service,
          'service',
          'has no add form; only Radarr, Sonarr and Lidarr can be added to',
        );
    }
  }

  void selectProfile(int id) =>
      state = state.copyWith(profileId: id, clearError: true);

  void selectRootFolder(String path) =>
      state = state.copyWith(rootFolder: path, clearError: true);

  void selectMetadataProfile(int id) =>
      state = state.copyWith(metadataProfileId: id, clearError: true);

  void setMonitored(bool value) => state = state.copyWith(monitored: value);

  void setSearchOnAdd(bool value) => state = state.copyWith(searchOnAdd: value);

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
    final metadataProfileId = state.metadataProfileId;
    if (profileId == null ||
        rootFolder == null ||
        (request is LidarrAddRequest && metadataProfileId == null)) {
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
              );
        case LidarrAddRequest(:final artist):
          await ref
              .read(lidarrServiceForProvider(request.instanceId))
              .addArtist(
                artist,
                qualityProfileId: profileId,
                metadataProfileId: metadataProfileId!,
                rootFolderPath: rootFolder,
                monitored: state.monitored,
                searchForMissingAlbums: state.searchOnAdd,
              );
      }
      ref.read(libraryAdditionsProvider.notifier).markAdded(request.libraryKey);
      // Cleared on the way out as well as on the way in. This entry is keyed on
      // the connection, not on the item, and outlives the sheet by however long
      // `autoDispose` takes: leaving the flag set means the next row's sheet
      // opens with `canSubmit` false and a dead Add button.
      state = state.copyWith(isSubmitting: false);
      return null;
    } catch (error) {
      final message = "Couldn't add ${request.title} to $connectionName.";
      state = state.copyWith(
        isSubmitting: false,
        error: message,
        errorDetail: '$error',
      );
      return message;
    }
  }

  /// Reports a post that was never attempted, in the same two registers a
  /// failed one uses, so the caller cannot mistake it for success.
  String _refuse(ArrAddRequest request, String detail) {
    final message = "Couldn't add ${request.title} to $connectionName.";
    state = state.copyWith(
      isSubmitting: false,
      error: message,
      errorDetail: detail,
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
