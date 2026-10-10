import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/import/data/manual_import_service.dart';
import 'package:cupola/features/import/domain/blocked_import.dart';
import 'package:cupola/features/import/domain/manual_import_display.dart';
import 'package:cupola/features/import/domain/manual_import_errors.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Preferences key for the folder a **connection** last scanned.
///
/// The rescue scene almost always returns to the same completed-downloads
/// folder, so Locate offers it back as a one-tap shortcut.
///
/// Keyed on the connection, not only on the service: two Radarrs are two
/// servers with two filesystems, and the shortcut keyed on `radarr` alone
/// offered the 4K box's completed-downloads path to a wizard bound to the HD
/// box — a path that may not exist there, and if it does is the wrong one.
/// An empty id keeps the historical key, so the single-connection setup that
/// wrote it keeps its shortcut.
String manualImportLastFolderKey(ServiceKey service, [String instanceId = '']) {
  final base = 'manual_import.last_folder.${service.name}';
  return instanceId.isEmpty ? base : '$base.$instanceId';
}

/// The folder a connection last scanned, and when — or null when there is none.
class ManualImportLastFolder {
  final String path;

  /// Null when the shortcut predates this field being written; the card then
  /// prints the path without a time rather than inventing one.
  final DateTime? scannedAt;

  const ManualImportLastFolder({required this.path, this.scannedAt});
}

/// The folder this connection last scanned, or null when there is none yet.
final manualImportLastFolderProvider =
    Provider.family<ManualImportLastFolder?, (ServiceKey, String)>((ref, key) {
      final (service, instanceId) = key;
      // Startup overrides the prefs provider; tests that don't override it get
      // the unimplemented throw, which for a convenience shortcut should mean
      // "no shortcut", not a crash.
      try {
        final prefs = ref.watch(sharedPreferencesProvider);
        final path = prefs.getString(
          manualImportLastFolderKey(service, instanceId),
        );
        if (path == null || path.isEmpty) return null;
        final stamp = prefs.getString(
          manualImportLastScanKey(service, instanceId),
        );
        return ManualImportLastFolder(
          path: path,
          scannedAt: stamp == null ? null : DateTime.tryParse(stamp),
        );
      } catch (_) {
        return null;
      }
    });

/// Preferences key for when that folder was last scanned.
String manualImportLastScanKey(ServiceKey service, [String instanceId = '']) {
  final base = 'manual_import.last_scan_at.${service.name}';
  return instanceId.isEmpty ? base : '$base.$instanceId';
}

const Object _noValue = Object();

final manualImportFlowProvider =
    NotifierProvider<ManualImportFlowNotifier, ManualImportFlowState>(
      ManualImportFlowNotifier.new,
    );

class ManualImportFlowState {
  final ServiceKey? service;

  /// The connection this flow is bound to, from the route's `?i=`.
  ///
  /// Empty means "whatever the lens was on when the flow started", which is
  /// what every link that predates the parameter carries. It is read once, at
  /// [ManualImportFlowNotifier.start], and never re-resolved: the wizard browses
  /// one server's filesystem and moves files into one server's library, so a
  /// lens that moves mid-scan must not take the files with it.
  final String instanceId;

  final int? targetId;
  final List<ManualImportRootFolder> rootFolders;
  final ManualImportFileSystemResult? fileSystem;
  final String? currentPath;
  final String? selectedFolder;
  final List<ManualImportItem> items;
  final Set<String> selectedPaths;

  /// Unmatched files the user has ticked to assign **together**.
  ///
  /// Separate from [selectedPaths] because they answer different questions:
  /// that one is "import these", this one is "these share an identity". The
  /// distinction is what stopped bulk assignment from being a blunt
  /// instrument — one series applied to every unmatched file in the folder
  /// happily matched playlists and other shows' episodes to it.
  final Set<String> fixSelectionPaths;

  final List<ManualImportItem> submittedItems;

  /// Paths already handed to a `ManualImport` command in this session.
  ///
  /// The flow used to keep the selection intact after submitting, so leaving
  /// Track and pressing Import again re-posted the same files. While the first
  /// command was still running that queued a duplicate import; once it had
  /// finished, the files had been moved into the library and the service
  /// answered with a `FileNotFoundException` for a path it had itself consumed.
  /// Recording what was submitted is what makes the second press impossible.
  final Set<String> submittedPaths;

  final List<ManualImportQualityOption> qualityOptions;
  final List<ManualImportLanguageOption> languageOptions;
  final ManualImportCommandStatus? command;
  final bool isLoadingBrowse;
  final bool isLoadingItems;
  final bool isSubmitting;
  final ManualImportMode importMode;
  final String? error;

  /// Set when this flow is the Review of a connection's blocked imports
  /// ([ManualImportFlowNotifier.startBlocked]) rather than a scan of a folder.
  final BlockedImportReview? blocked;

  /// When [command] was first seen finished, on this device's clock: the
  /// arr's own `ended` is its server's, and a self-hosted clock that runs
  /// ten minutes off would date the import before it happened.
  final DateTime? commandEndedAt;

  const ManualImportFlowState({
    this.service,
    this.instanceId = '',
    this.targetId,
    this.rootFolders = const [],
    this.fileSystem,
    this.currentPath,
    this.selectedFolder,
    this.items = const [],
    this.selectedPaths = const {},
    this.fixSelectionPaths = const {},
    this.submittedItems = const [],
    this.submittedPaths = const {},
    this.qualityOptions = const [],
    this.languageOptions = const [],
    this.command,
    this.isLoadingBrowse = false,
    this.isLoadingItems = false,
    this.isSubmitting = false,
    this.importMode = ManualImportMode.auto,
    this.error,
    this.blocked,
    this.commandEndedAt,
  });

  List<ManualImportItem> get selectedItems => items
      .where((item) => selectedPaths.contains(item.path))
      .toList(growable: false);

  /// Paths that must not be submitted again.
  ///
  /// A batch is spent while its command is running and once it has completed —
  /// the files are being, or have been, moved into the library. A **failed**
  /// command releases them: the file may well still be on disk, and retrying
  /// after fixing the cause is exactly what the user should be able to do.
  Set<String> get blockedPaths {
    final command = this.command;
    if (command == null || command.isFailure) return const {};
    return submittedPaths;
  }

  /// Files handed to the current command, still shown so the list stays honest
  /// about where they went.
  List<ManualImportItem> get inFlightItems {
    final blocked = blockedPaths;
    if (blocked.isEmpty) return const [];
    return items
        .where((item) => blocked.contains(item.path))
        .toList(growable: false);
  }

  /// Fully matched files — the only ones the import checkbox can include.
  List<ManualImportItem> get readyItems {
    final service = this.service;
    if (service == null) return const [];
    final blocked = blockedPaths;
    return items
        .where(
          (item) =>
              item.isReadyForImportFor(service) && !blocked.contains(item.path),
        )
        .toList(growable: false);
  }

  /// Files that need an identity before they can be imported.
  ///
  /// Only files the service could actually import: a Sonarr scan of a real
  /// downloads folder also returns playlists, artwork and music, and counting
  /// those as "needs attention" makes the number unactionable — 26 items to fix
  /// when only a handful are episodes. Those land in [otherItems] instead.
  List<ManualImportItem> get attentionItems {
    final service = this.service;
    if (service == null) return const [];
    final blocked = blockedPaths;
    return items
        .where(
          (item) =>
              item.isSelectable &&
              !item.isReadyForImportFor(service) &&
              !blocked.contains(item.path) &&
              manualImportIsSupportedFile(service, item),
        )
        .toList(growable: false);
  }

  /// Files of a kind this service does not import — kept visible, and still
  /// fixable, but out of the way.
  List<ManualImportItem> get otherItems {
    final service = this.service;
    if (service == null) return const [];
    final blocked = blockedPaths;
    return items
        .where(
          (item) =>
              item.isSelectable &&
              !item.isReadyForImportFor(service) &&
              !blocked.contains(item.path) &&
              !manualImportIsSupportedFile(service, item),
        )
        .toList(growable: false);
  }

  /// The unmatched files ticked for a shared assignment.
  List<ManualImportItem> get fixSelectionItems => items
      .where((item) => fixSelectionPaths.contains(item.path))
      .toList(growable: false);

  /// Files the service already holds.
  ///
  /// The scan asks for them deliberately (`filterExistingFiles: false`), because
  /// with the service's default filter on, an already-imported file is simply
  /// absent — and "did I already take this one?" then has no answer anywhere in
  /// the app. They are listed inline with everything else, and a user who wants
  /// one taken again can tick it; see [ManualImportItem.isReimportableFor].
  List<ManualImportItem> get importedItems {
    final blocked = blockedPaths;
    return items
        .where((item) => item.isAlreadyImported && !blocked.contains(item.path))
        .toList(growable: false);
  }

  /// Everything in the scan this service could actually take: matched files,
  /// files still waiting for an identity, and files it already holds.
  ///
  /// The denominator the footer summary prints against. [otherItems] is
  /// deliberately outside it — a real downloads folder carries dozens of
  /// playlists, NFOs and artwork, and counting them would turn "3 of 5
  /// selected" into "3 of 61 selected", a fraction about a problem the user
  /// does not have.
  int get importableCount =>
      readyItems.length + attentionItems.length + importedItems.length;

  /// Bytes the current selection would move.
  int get selectedBytes => selectedItems.fold(
    0,
    (total, item) => total + (item.size > 0 ? item.size : 0),
  );

  /// Already-imported files the user has ticked to send over again.
  List<ManualImportItem> get selectedReimportItems => selectedItems
      .where((item) => item.isAlreadyImported)
      .toList(growable: false);

  bool get allReadySelected =>
      readyItems.isNotEmpty &&
      readyItems.every((item) => selectedPaths.contains(item.path));

  bool get canImportSelected =>
      service != null &&
      selectedItems.isNotEmpty &&
      selectedItems.every(
        (item) =>
            item.isSubmittableFor(service!) &&
            !blockedPaths.contains(item.path),
      ) &&
      !isSubmitting;

  ManualImportFlowState copyWith({
    Object? service = _noValue,
    String? instanceId,
    Object? targetId = _noValue,
    List<ManualImportRootFolder>? rootFolders,
    Object? fileSystem = _noValue,
    Object? currentPath = _noValue,
    Object? selectedFolder = _noValue,
    List<ManualImportItem>? items,
    Set<String>? selectedPaths,
    Set<String>? fixSelectionPaths,
    List<ManualImportItem>? submittedItems,
    Set<String>? submittedPaths,
    List<ManualImportQualityOption>? qualityOptions,
    List<ManualImportLanguageOption>? languageOptions,
    Object? command = _noValue,
    bool? isLoadingBrowse,
    bool? isLoadingItems,
    bool? isSubmitting,
    ManualImportMode? importMode,
    Object? error = _noValue,
    Object? blocked = _noValue,
    Object? commandEndedAt = _noValue,
  }) {
    return ManualImportFlowState(
      service: identical(service, _noValue)
          ? this.service
          : service as ServiceKey?,
      instanceId: instanceId ?? this.instanceId,
      targetId: identical(targetId, _noValue)
          ? this.targetId
          : targetId as int?,
      rootFolders: rootFolders ?? this.rootFolders,
      fileSystem: identical(fileSystem, _noValue)
          ? this.fileSystem
          : fileSystem as ManualImportFileSystemResult?,
      currentPath: identical(currentPath, _noValue)
          ? this.currentPath
          : currentPath as String?,
      selectedFolder: identical(selectedFolder, _noValue)
          ? this.selectedFolder
          : selectedFolder as String?,
      items: items ?? this.items,
      selectedPaths: selectedPaths ?? this.selectedPaths,
      fixSelectionPaths: fixSelectionPaths ?? this.fixSelectionPaths,
      submittedItems: submittedItems ?? this.submittedItems,
      submittedPaths: submittedPaths ?? this.submittedPaths,
      qualityOptions: qualityOptions ?? this.qualityOptions,
      languageOptions: languageOptions ?? this.languageOptions,
      command: identical(command, _noValue)
          ? this.command
          : command as ManualImportCommandStatus?,
      isLoadingBrowse: isLoadingBrowse ?? this.isLoadingBrowse,
      isLoadingItems: isLoadingItems ?? this.isLoadingItems,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      importMode: importMode ?? this.importMode,
      error: identical(error, _noValue) ? this.error : error as String?,
      blocked: identical(blocked, _noValue)
          ? this.blocked
          : blocked as BlockedImportReview?,
      commandEndedAt: identical(commandEndedAt, _noValue)
          ? this.commandEndedAt
          : commandEndedAt as DateTime?,
    );
  }
}

class ManualImportFlowNotifier extends Notifier<ManualImportFlowState> {
  @override
  ManualImportFlowState build() => const ManualImportFlowState();

  /// The client for the connection this flow is bound to.
  ///
  /// Every call in this notifier goes through here rather than through the
  /// plain per-service provider, which reads the lens. With two Radarrs that
  /// meant a wizard opened on the HD box browsed the HD filesystem only until
  /// the lens moved, and then posted the import to the 4K one.
  ManualImportService _api(ServiceKey service) =>
      ref.read(manualImportServiceForProvider((service, state.instanceId)));

  /// The device's clock, as Activity reads it.
  DateTime _clock() => ref.read(stallClockProvider)();

  Future<void> start(
    ServiceKey service, {
    String? instanceId,
    int? targetId,
    bool force = false,
    String? initialPath,
  }) async {
    final connection = instanceId ?? '';
    if (!force &&
        initialPath == null &&
        state.service == service &&
        // A different connection is a different server: same service, same
        // target, and every path already on screen belongs to someone else.
        state.instanceId == connection &&
        state.targetId == targetId &&
        state.rootFolders.isNotEmpty) {
      return;
    }

    state = ManualImportFlowState(
      service: service,
      instanceId: connection,
      targetId: targetId,
      isLoadingBrowse: true,
    );

    try {
      final api = _api(service);
      final rootFolders = await api.getRootFolders();
      final defaultPath = initialPath ?? '/';
      state = state.copyWith(
        rootFolders: rootFolders,
        isLoadingBrowse: false,
        currentPath: defaultPath,
        selectedFolder: defaultPath,
        error: null,
      );
      await selectFolder(defaultPath);
    } catch (error) {
      state = state.copyWith(
        isLoadingBrowse: false,
        error: mapImportError(error, service),
      );
    }
  }

  /// Opens the Review of every download [service]'s connection finished and
  /// would not import: what Needs you's `Review 18` leads to.
  ///
  /// The downloads are the queue's, as Needs you counts them, so the Review
  /// holds what the card promised. Each one's files are read by the client's
  /// id for it (`GET /manualimport?downloadId=`), as the arr's own queue reads
  /// them, never by scanning a folder, which would sweep in whatever else the
  /// client left beside them; one that will not list its files takes nobody
  /// else's with it. The files the arr would take as they are arrive
  /// selected; the rest wait for the user.
  ///
  /// An import of this connection still running keeps its command and its
  /// files, which stay out of the Review: they are on their way already.
  Future<void> startBlocked(ServiceKey service, {String? instanceId}) async {
    final connection = instanceId ?? '';
    final previous = state;
    final running =
        previous.blocked != null &&
        previous.service == service &&
        previous.instanceId == connection &&
        (previous.command?.isActive ?? false);
    state = ManualImportFlowState(
      service: service,
      instanceId: connection,
      isLoadingItems: true,
      blocked: const BlockedImportReview(),
      command: running ? previous.command : null,
      submittedItems: running ? previous.submittedItems : const [],
      submittedPaths: running ? previous.submittedPaths : const {},
    );

    try {
      final inFlight = await ref.read(servicesInFlightProvider.future);
      final lens = ref.read(activeInstanceProvider(service))?.id ?? '';
      final downloads = blockedDownloadsOf(
        inFlight.faults,
        service,
        connection: connection,
        lens: lens,
      );
      final api = _api(service);
      final reads = await Future.wait([
        for (final download in downloads)
          api
              .getDownloadImportItems(
                downloadId: download.downloadId,
                mediaId: download.mediaId,
              )
              .then<List<ManualImportItem>?>(
                (items) => items,
                onError: (Object _) => null,
              ),
      ]);
      final spent = state.submittedPaths;
      final seen = <String>{};
      final items = [
        for (final read in reads)
          for (final item in read ?? const <ManualImportItem>[])
            if (!spent.contains(item.path) && seen.add(item.path)) item,
      ];
      final split = splitBlockedImport(service, items);
      final replacing = await _replacedQualities(service, api, [
        ...split.clear,
        ...split.needYou,
      ]);
      state = state.copyWith(
        items: [...split.clear, ...split.needYou],
        selectedPaths: {for (final item in split.clear) item.path},
        blocked: BlockedImportReview(
          downloads: downloads,
          needYouPaths: [for (final item in split.needYou) item.path],
          needYouKinds: {
            for (final item in split.needYou)
              item.path: needYouKindOf(service, item),
          },
          leftOut: split.leftOut,
          unread: reads.where((read) => read == null).length,
          replacing: replacing,
        ),
        isLoadingItems: false,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingItems: false,
        error: mapImportError(error, service),
      );
    }
  }

  /// By path, the quality of the library file each of [items] replaces:
  /// Sonarr's from the series' episode files, one read per series; Radarr's
  /// from the movie's own file. A read that fails says nothing, and the
  /// Review only loses the words `each replaces a 720p file`.
  Future<Map<String, String>> _replacedQualities(
    ServiceKey service,
    ManualImportService api,
    List<ManualImportItem> items,
  ) async {
    final replacing = <String, String>{};
    switch (service) {
      case ServiceKey.sonarr:
        final seriesIds = {
          for (final item in items)
            if ((intOrNull(item.series?['id']) ?? 0) > 0)
              intOrNull(item.series!['id'])!,
        };
        final qualities = <int, String>{};
        await Future.wait([
          for (final id in seriesIds)
            api
                .getEpisodeFileQualities(id)
                .then(qualities.addAll, onError: (Object _) {}),
        ]);
        for (final item in items) {
          for (final episode in item.episodes) {
            final name = qualities[intOrNull(episode['episodeFileId']) ?? 0];
            if (name != null) {
              replacing[item.path] = name;
              break;
            }
          }
        }
      case ServiceKey.radarr:
        for (final item in items) {
          final file = mapOrNull(item.movie?['movieFile']);
          final name = stringOrNull(
            mapOrNull(mapOrNull(file?['quality'])?['quality'])?['name'],
          );
          if (name != null) replacing[item.path] = name;
        }
      case _:
        break;
    }
    return replacing;
  }

  /// Places a file Sonarr could not on [season] and [episode] of the series
  /// it was grabbed for, and adds it to the import. The words of what stood
  /// in the way, or null once it is placed.
  Future<String?> placeEpisode(
    ManualImportItem item, {
    required int season,
    required int episode,
  }) async {
    final service = state.service;
    final series = item.series;
    final seriesId = intOrNull(series?['id']) ?? 0;
    if (service != ServiceKey.sonarr || series == null || seriesId <= 0) {
      return "This file isn't from a series.";
    }
    try {
      final episodes = await getEpisodes(
        seriesId: seriesId,
        seasonNumber: season,
      );
      final match = episodes
          .where(
            (each) =>
                each.seasonNumber == season && each.episodeNumber == episode,
          )
          .firstOrNull;
      if (match == null) {
        return '${seasonChipLabel(season)} has no '
            '${formatEpisodeOrdinal(episode)}.';
      }
      final resolved = await applyFixAssignment(
        item,
        ManualImportFixAssignment(
          match: ManualImportLookupResult.fromJson(service!, series),
          episode: match,
          episodes: [match],
        ),
      );
      return resolved == null ? state.error : null;
    } catch (error) {
      return mapImportError(error, ServiceKey.sonarr);
    }
  }

  Future<void> selectFolder(String path) async {
    final service = state.service;
    if (service == null || path.isEmpty) return;

    state = state.copyWith(
      currentPath: path,
      selectedFolder: path,
      fileSystem: null,
      isLoadingBrowse: true,
      error: null,
    );

    try {
      final api = _api(service);
      final fileSystem = await api.getFileSystem(path);
      state = state.copyWith(fileSystem: fileSystem, isLoadingBrowse: false);
    } catch (error) {
      state = state.copyWith(
        isLoadingBrowse: false,
        error: mapImportError(error, service),
      );
    }
  }

  Future<void> loadSelectedFolderItems() async {
    final items = await _refreshSelectedFolderItems(clearItems: true);
    if (items.isNotEmpty || state.error == null) _persistLastFolder();
    await _applyTargetPreselection();
  }

  /// Remembers the scanned folder, and when, so Locate can offer it back next
  /// time with a "2 h ago" that says whether it is still the right one.
  void _persistLastFolder() {
    final service = state.service;
    final folder = state.selectedFolder;
    if (service == null || folder == null || folder.isEmpty || folder == '/') {
      return;
    }
    final connection = state.instanceId;
    // Best-effort convenience: tests run without a prefs override, and a
    // missing shortcut must never fail a scan that succeeded.
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      prefs.setString(manualImportLastFolderKey(service, connection), folder);
      prefs.setString(
        manualImportLastScanKey(service, connection),
        DateTime.now().toUtc().toIso8601String(),
      );
      ref.invalidate(manualImportLastFolderProvider((service, connection)));
    } catch (_) {}
  }

  /// When the flow was launched from a specific movie/series/artist
  /// ([ManualImportFlowState.targetId]), pre-assign that title as the match for
  /// files the server could not identify — so the user doesn't have to re-match
  /// what they already came from. Movies resolve fully; for series/artists this
  /// only fills in files whose season+episode / album+track the server already
  /// parsed. Anything ambiguous is left untouched for the Fix sheet.
  ///
  /// Crucially this reuses the exact same guarded path as the manual bulk-fix
  /// ([applyBulkFixAssignments] + [libraryGuardError]) and only applies an
  /// assignment that is already valid, so it can never produce a broken import
  /// payload; the pre-filled matches remain fully editable before confirming.
  ///
  /// Three things keep the guess from becoming a decision.
  ///
  /// It only ever touches files the service could import at all
  /// ([manualImportIsSupportedFile]) — Radarr's guard is satisfied by a
  /// `movieId` alone, so without that filter a scan of a shared downloads folder
  /// wrote the launch target into every unmatched row it returned: samples,
  /// subtitles, artwork, NFOs.
  ///
  /// It only touches files whose *name* says they are the target
  /// ([manualImportFileNamesTitle]). [targetId] survives every
  /// [selectFolder]/scan for the rest of the flow, and nothing about the launch
  /// pins it to a folder — the entry points that carry a target carry no path —
  /// so "any video file in whatever folder is on screen" meant a scan of the
  /// whole downloads root labelled every unidentified rip in it with the movie
  /// the user happened to come from.
  ///
  /// And it does **not** select what it assigns: a guess the user never reviewed
  /// must not arrive pre-ticked in the batch that "Confirm import" sends.
  Future<void> _applyTargetPreselection() async {
    final service = state.service;
    final targetId = state.targetId;
    if (service == null || targetId == null || targetId <= 0) return;

    final importable = state.items
        .where(
          (item) =>
              item.isSelectable &&
              !item.hasMatchFor(service) &&
              manualImportIsSupportedFile(service, item),
        )
        .toList(growable: false);
    if (importable.isEmpty) return;

    ManualImportLookupResult? target;
    try {
      final matches = await getLibraryMatches();
      for (final option in matches) {
        if (option.id == targetId) {
          target = option;
          break;
        }
      }
    } catch (_) {
      return; // Best-effort: fall back to fully manual matching.
    }
    final match = target;
    if (match == null) return;

    final unmatched = importable
        .where((item) => manualImportFileNamesTitle(match.title, item))
        .toList(growable: false);
    if (unmatched.isEmpty) return;

    final assignments = <ManualImportItem, ManualImportFixAssignment>{};
    for (final item in unmatched) {
      final parsed = _assignmentForItem(service, item);
      final candidate = ManualImportFixAssignment(
        match: match,
        episode: parsed.episode,
        episodes: parsed.episodes,
        album: parsed.album,
        track: parsed.track,
        tracks: parsed.tracks,
      );
      if (libraryGuardError(service, candidate) == null) {
        assignments[item] = candidate;
      }
    }

    if (assignments.isNotEmpty) {
      await applyBulkFixAssignments(assignments, select: false);
    }
  }

  Future<List<ManualImportItem>> _refreshSelectedFolderItems({
    bool preserveSelection = false,
    bool clearItems = false,
    bool preserveCommand = false,
  }) async {
    final service = state.service;
    final folder = state.selectedFolder;
    if (service == null || folder == null || folder.isEmpty) return const [];

    final previousSelected = state.selectedPaths;
    // A fresh scan of a folder starts a new session and drops any command; a
    // refresh *of the same* scan must keep it, or the files it is importing
    // would come back selectable mid-flight.
    final Object? commandArg = preserveCommand ? _noValue : null;
    final blocked = preserveCommand ? state.blockedPaths : const <String>{};

    state = state.copyWith(
      isLoadingItems: true,
      items: clearItems ? const [] : null,
      selectedPaths: preserveSelection ? null : const {},
      fixSelectionPaths: const {},
      command: commandArg,
      submittedPaths: preserveCommand ? null : const {},
      error: null,
    );

    try {
      final api = _api(service);
      final items = await api.getManualImportItems(
        folder: folder,
        // Always: the files the service already holds are part of the review,
        // not noise. Left filtered, an already-imported file simply vanishes
        // from the scan — which is how "is this one already in the library?"
        // came to have no answer, and how a folder that looked half-empty was
        // actually reporting a successful earlier import.
        filterExistingFiles: false,
      );
      // Only files that are actually importable are preselected. Selecting the
      // unmatched ones too is how the old flow ended up with a confirm button
      // that one bad file could hold hostage — and an already-imported file is
      // never preselected either, because sending one again is a decision the
      // user makes, not a default.
      //
      // Nor is a sample. It is matched as precisely as the rip beside it, so it
      // passed every readiness test and arrived ticked: "Import 4 files" was
      // five, and the fifth was a 42 MB trailer about to be moved into the
      // library under the feature's name. The row stays visible and tickable —
      // this removes a default, not a capability.
      final readyPaths = items
          .where(
            (item) =>
                item.isReadyForImportFor(service) &&
                !item.isSample &&
                !blocked.contains(item.path),
          )
          .map((item) => item.path)
          .toSet();
      // A preserved selection may legitimately hold a ticked re-import, so the
      // surviving set is everything submittable rather than everything ready.
      final selectedPaths = preserveSelection
          ? previousSelected.intersection(
              items
                  .where(
                    (item) =>
                        item.isSubmittableFor(service) &&
                        !blocked.contains(item.path),
                  )
                  .map((item) => item.path)
                  .toSet(),
            )
          : readyPaths;
      state = state.copyWith(
        items: items,
        selectedPaths: selectedPaths,
        isLoadingItems: false,
      );
      return items;
    } catch (error) {
      state = state.copyWith(
        isLoadingItems: false,
        error: mapImportError(error, service),
      );
      return const [];
    }
  }

  void toggleItem(ManualImportItem item, bool selected) {
    final service = state.service;
    // A matched file, or an already-imported one the user is deliberately
    // sending again. An unmatched file gets here through the fix flow, which
    // selects it once it becomes valid. A file already handed to a command in
    // this session is never selectable again.
    if (service == null ||
        !item.isSubmittableFor(service) ||
        state.blockedPaths.contains(item.path)) {
      return;
    }
    final next = {...state.selectedPaths};
    if (selected) {
      next.add(item.path);
    } else {
      next.remove(item.path);
    }
    state = state.copyWith(selectedPaths: next);
  }

  void toggleAllReady() {
    if (state.allReadySelected) {
      state = state.copyWith(selectedPaths: const {});
      return;
    }

    state = state.copyWith(
      selectedPaths: state.readyItems.map((item) => item.path).toSet(),
    );
  }

  /// Replaces the selection with exactly [items].
  ///
  /// The payoff of the filter: narrow to one series, take those and nothing
  /// else. Without it a filtered view still imports whatever was selected off
  /// screen, which is the one thing a user who filtered did not ask for.
  void selectOnly(List<ManualImportItem> items) {
    final service = state.service;
    if (service == null) return;
    state = state.copyWith(
      selectedPaths: items
          .where((item) => item.isReadyForImportFor(service))
          .map((item) => item.path)
          .toSet(),
    );
  }

  /// Selects or clears a whole group of ready files at once.
  ///
  /// The gesture the grouped list exists for: one tap to take every episode of
  /// one series, rather than forty taps down a flat list of four hundred.
  void setGroupSelected(List<ManualImportItem> group, bool selected) {
    final service = state.service;
    if (service == null) return;
    final paths = group
        .where((item) => item.isReadyForImportFor(service))
        .map((item) => item.path)
        .toSet();
    if (paths.isEmpty) return;

    final next = {...state.selectedPaths};
    if (selected) {
      next.addAll(paths);
    } else {
      next.removeAll(paths);
    }
    state = state.copyWith(selectedPaths: next);
  }

  /// Ticks an unmatched file into the shared-assignment selection.
  void toggleFixSelection(ManualImportItem item, bool selected) {
    final next = {...state.fixSelectionPaths};
    if (selected) {
      next.add(item.path);
    } else {
      next.remove(item.path);
    }
    state = state.copyWith(fixSelectionPaths: next);
  }

  void clearFixSelection() {
    if (state.fixSelectionPaths.isEmpty) return;
    state = state.copyWith(fixSelectionPaths: const {});
  }

  Future<List<ManualImportLookupResult>> lookup(String term) async {
    final service = state.service;
    if (service == null) return const [];
    return _api(service).lookup(term);
  }

  Future<List<ManualImportLookupResult>> getLibraryMatches() async {
    final service = state.service;
    if (service == null) return const [];
    return _api(service).getLibraryMatches();
  }

  Future<List<ManualImportQualityOption>> getQualityOptions() async {
    final service = state.service;
    if (service == null) return const [];
    if (state.qualityOptions.isNotEmpty) return state.qualityOptions;

    try {
      final options = await _api(service).getQualityOptions();
      state = state.copyWith(qualityOptions: options);
      return options;
    } catch (error) {
      state = state.copyWith(error: mapImportError(error, service));
      return const [];
    }
  }

  Future<List<ManualImportLanguageOption>> getLanguageOptions() async {
    final service = state.service;
    if (service == null) return const [];
    if (state.languageOptions.isNotEmpty) return state.languageOptions;

    try {
      final options = await _api(service).getLanguageOptions();
      state = state.copyWith(languageOptions: options);
      return options;
    } catch (error) {
      state = state.copyWith(error: mapImportError(error, service));
      return const [];
    }
  }

  void setImportMode(ManualImportMode importMode) {
    state = state.copyWith(importMode: importMode);
  }

  /// Applies a fix assignment to a single item locally — no API call.
  ///
  /// The actual import is triggered separately via [confirmImport], which
  /// POSTs the `ManualImport` command for all currently selected items.
  /// This method only updates the in-memory item so that
  /// `isReadyForImportFor(service)` returns true and the item can be added
  /// to the selection.
  Future<ManualImportItem?> applyFixAssignment(
    ManualImportItem item,
    ManualImportFixAssignment assignment,
  ) async {
    final service = state.service;
    if (service == null) return null;

    final guardError = libraryGuardError(service, assignment);
    if (guardError != null) {
      state = state.copyWith(error: guardError);
      return null;
    }

    final resolved = item.resolvedWithAssignment(service, assignment);
    state = state.copyWith(
      items: [
        // Matched on the path alone. The id used to be an alternative here, but
        // it is not an identity: `ManualImportItem.fromJson` falls back to
        // `path.hashCode` when the server sends none, so the clause was
        // redundant for every conforming payload while leaving one service that
        // returns a constant id able to splatter one resolved item over every
        // row in the scan. The path is what the import command sends, so the
        // path is what selects the row it belongs to.
        for (final existing in state.items)
          if (existing.path == item.path) resolved else existing,
      ],
      // Auto-select the now-ready item so "Confirm import" picks it up.
      selectedPaths: {...state.selectedPaths, resolved.path},
      error: null,
    );
    return resolved;
  }

  Future<ManualImportItem?> updateItemMetadata(
    ManualImportItem item, {
    ManualImportQualityOption? quality,
    List<ManualImportLanguageOption>? languages,
  }) async {
    final service = state.service;
    if (service == null) return null;
    if (!item.hasMatchFor(service)) return item;

    final qualityOverride = quality?.toQualityModel(
      currentQuality: item.quality,
    );
    final languageOverride = languages
        ?.map((item) => item.toLanguageResource())
        .toList(growable: false);
    final draft = item.withMetadataOverrides(
      quality: qualityOverride,
      languages: languageOverride,
    );

    final assignment = _assignmentForItem(service, draft);

    return applyFixAssignment(draft, assignment);
  }

  /// Applies fix assignments to a batch of items locally — no API call.
  ///
  /// Mirrors [applyFixAssignment] for the bulk fix flow. The actual import
  /// is triggered separately via [confirmImport].
  ///
  /// [select] adds the now-ready files to the import selection, which is right
  /// when the user just assigned them by hand and wrong when the app guessed on
  /// their behalf — see [_applyTargetPreselection].
  Future<List<ManualImportItem>> applyBulkFixAssignments(
    Map<ManualImportItem, ManualImportFixAssignment> assignments, {
    bool select = true,
  }) async {
    final service = state.service;
    if (service == null || assignments.isEmpty) return const [];

    // Library guard — fail fast, don't update state for invalid assignments.
    for (final entry in assignments.entries) {
      final guardError = libraryGuardError(service, entry.value);
      if (guardError != null) {
        state = state.copyWith(error: guardError);
        return const [];
      }
    }

    final updatedByPath = <String, ManualImportItem>{};
    for (final entry in assignments.entries) {
      final resolved = entry.key.resolvedWithAssignment(service, entry.value);
      updatedByPath[entry.key.path] = resolved;
    }
    state = state.copyWith(
      items: [
        for (final existing in state.items)
          updatedByPath[existing.path] ?? existing,
      ],
      // Auto-select the now-ready items so "Confirm import" picks them up.
      selectedPaths: select
          ? {...state.selectedPaths, ...updatedByPath.keys}
          : state.selectedPaths,
      // They are no longer unmatched, so the shared-assignment tick is spent.
      fixSelectionPaths: state.fixSelectionPaths.difference(
        updatedByPath.keys.toSet(),
      ),
      error: null,
    );
    final refreshed = state.items
        .where((item) => updatedByPath.containsKey(item.path))
        .toList(growable: false);
    return refreshed;
  }

  Future<List<ManualImportEpisode>> getEpisodes({
    required int seriesId,
    int? seasonNumber,
  }) async {
    final service = state.service;
    if (service != ServiceKey.sonarr) return const [];
    return _api(
      service!,
    ).getEpisodes(seriesId: seriesId, seasonNumber: seasonNumber);
  }

  Future<List<ManualImportAlbum>> getAlbums(int artistId) async {
    final service = state.service;
    if (service != ServiceKey.lidarr) return const [];
    return _api(service!).getAlbums(artistId);
  }

  Future<List<ManualImportTrack>> getTracks(int albumId) async {
    final service = state.service;
    if (service != ServiceKey.lidarr) return const [];
    return _api(service!).getTracks(albumId: albumId);
  }

  /// Posts the selected files as one `ManualImport` command.
  ///
  /// Returns the existing command, without posting, when there is nothing new
  /// to send — so navigating back into Track is always safe and pressing the
  /// button twice can never queue the same files twice.
  Future<ManualImportCommandStatus?> confirmImport() async {
    final service = state.service;
    if (service == null) return null;

    // Everything already handed over: this is a navigation, not a submission.
    final files = state.selectedItems
        .where((item) => !state.blockedPaths.contains(item.path))
        .toList(growable: false);
    if (files.isEmpty) return state.command;
    if (!state.canImportSelected) return null;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final command = await _startCommand(service, files);
      final submitted = files.map((item) => item.path).toSet();
      state = state.copyWith(
        command: command,
        commandEndedAt: command.isActive ? null : _clock(),
        submittedItems: files,
        // The batch is spent: drop it from the selection and record it, so the
        // Review screen behind Track offers no way to send it again.
        submittedPaths: {...state.submittedPaths, ...submitted},
        selectedPaths: state.selectedPaths.difference(submitted),
        isSubmitting: false,
      );
      return command;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        error: mapImportError(error, service),
      );
      return null;
    }
  }

  Future<ManualImportCommandStatus> _startCommand(
    ServiceKey service,
    List<ManualImportItem> files,
  ) {
    return _api(service).startManualImport(
      files,
      importMode: state.importMode,
      // Only when the batch genuinely contains a file the service already
      // holds: this flag lets Lidarr overwrite what is in the library, and it
      // has no business being on for an ordinary import.
      replaceExistingFiles: files.any((item) => item.isAlreadyImported),
    );
  }

  /// Re-posts the batch a failed command left behind.
  ///
  /// The failed leaf of Track is the one place this is reachable, and it is
  /// also the only command state in which [ManualImportFlowState.blockedPaths]
  /// releases those paths: a failed import leaves the files where they were, so
  /// retrying after fixing the cause — a full disk, a permission, a service
  /// restart — is exactly what should happen next.
  ///
  /// It re-posts [ManualImportFlowState.submittedItems] rather than the
  /// selection, because confirming spent the selection; making the user walk
  /// back to Review and re-tick the same files would be asking them to re-decide
  /// something they already decided.
  Future<ManualImportCommandStatus?> retryImport() async {
    final service = state.service;
    final command = state.command;
    final files = state.submittedItems;
    if (service == null || command == null || !command.isFailure) return null;
    if (files.isEmpty || state.isSubmitting) return null;

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final next = await _startCommand(service, files);
      state = state.copyWith(
        command: next,
        commandEndedAt: next.isActive ? null : _clock(),
        isSubmitting: false,
      );
      return next;
    } catch (error) {
      state = state.copyWith(
        isSubmitting: false,
        error: mapImportError(error, service),
      );
      return null;
    }
  }

  /// Re-reads the folder when the user comes back from Track.
  ///
  /// The service is the authority on what is still on disk: files it imported
  /// are gone, files it failed on are still there. Keeping the command and the
  /// submitted set through the refresh is what stops a still-present file from
  /// quietly becoming selectable again while its import is in flight.
  Future<void> refreshAfterImport() async {
    if (state.command == null || state.isLoadingItems) return;
    await _refreshSelectedFolderItems(
      preserveSelection: true,
      preserveCommand: true,
    );
  }

  Future<void> pollCommand() async {
    final service = state.service;
    final command = state.command;
    if (service == null || command == null || !command.isActive) return;

    try {
      final api = _api(service);
      final next = await api.getCommand(command.id);
      state = state.copyWith(
        command: next,
        commandEndedAt: next.isActive ? null : _clock(),
      );
    } catch (error) {
      state = state.copyWith(error: mapImportError(error, service));
    }
  }
}

ManualImportFixAssignment _assignmentForItem(
  ServiceKey service,
  ManualImportItem item,
) {
  final matchPayload = switch (service) {
    ServiceKey.radarr => item.movie ?? const <String, dynamic>{},
    ServiceKey.sonarr => item.series ?? const <String, dynamic>{},
    ServiceKey.lidarr => item.artist ?? const <String, dynamic>{},
    _ => const <String, dynamic>{},
  };
  final episodes = service == ServiceKey.sonarr
      ? item.episodes
            .map(ManualImportEpisode.fromJson)
            .where((item) => item.id > 0)
            .toList(growable: false)
      : const <ManualImportEpisode>[];
  final episode = service == ServiceKey.sonarr && item.episodes.isNotEmpty
      ? ManualImportEpisode.fromJson(item.episodes.first)
      : null;
  final tracks = service == ServiceKey.lidarr
      ? item.tracks
            .map(ManualImportTrack.fromJson)
            .where((item) => item.id > 0)
            .toList(growable: false)
      : const <ManualImportTrack>[];
  final track = service == ServiceKey.lidarr && item.tracks.isNotEmpty
      ? ManualImportTrack.fromJson(item.tracks.first)
      : null;

  return ManualImportFixAssignment(
    match: ManualImportLookupResult.fromJson(service, matchPayload),
    episode: episode,
    episodes: episodes,
    album: service == ServiceKey.lidarr && item.album != null
        ? ManualImportAlbum.fromJson(item.album!)
        : null,
    track: track,
    tracks: tracks,
  );
}

/// The downloads [service]'s connection finished and would not import, from
/// the queue's faults: the ones Needs you counts on that connection's card.
/// An empty id on either side is the lens, as a link that names none is.
List<BlockedDownload> blockedDownloadsOf(
  Iterable<ServiceQueueItem> faults,
  ServiceKey service, {
  required String connection,
  required String lens,
}) {
  String resolved(String id) => id.isEmpty ? lens : id;
  final seen = <String>{};
  return [
    for (final item in faults)
      if (item.fault == InFlightFault.needsImport &&
          item.service == service &&
          resolved(item.instanceId) == resolved(connection))
        if (item.downloadId case final downloadId?
            when downloadId.isNotEmpty && seen.add(downloadId))
          BlockedDownload(
            downloadId: downloadId,
            title: item.title,
            mediaId: item.mediaId,
            message: item.warning,
          ),
  ];
}
