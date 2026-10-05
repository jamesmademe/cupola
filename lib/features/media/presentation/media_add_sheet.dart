import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_monitor.dart';
import 'package:cupola/features/series/domain/sonarr_series_type.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Adds a title nobody holds to its arr: a film to Radarr, a series to
/// Sonarr. Which connection, the quality profile and root folder it lands
/// under, what the arr looks for (for a film, whether it monitors it; for a
/// series, which episodes, and how it numbers them), and whether it searches
/// now.
///
/// [connections] are the [arr] connections set up, the first chosen. The
/// sheet resolves to the one the title was added to, null when it closed
/// without adding. The title is posted as that connection looks it up
/// ([mediaAddLookupProvider] by TMDB's id, [mediaSonarrAddLookupProvider] by
/// TVDB's, else TMDB's), with the form the global search's add uses
/// ([arrAddFormProvider]).
Future<ServiceInstance?> showMediaAddSheet(
  BuildContext context, {
  required ServiceKey arr,
  required List<ServiceInstance> connections,
  required String Function(ServiceInstance connection) name,
  required String title,
  int? tmdbId,
  int? tvdbId,
  String? year,
  TitleLight? light,
}) {
  assert(connections.isNotEmpty, 'nothing to add to');
  return AppBottomSheet.show<ServiceInstance>(
    context: context,
    // One connection: the sheet names it. More: the pills under it do.
    title:
        'Add to ${connections.length == 1 ? name(connections.single) : arr.title}',
    subtitle: (year ?? '').isEmpty ? title : '$title · $year',
    showClose: true,
    builder: (_) => MediaAddSheet(
      arr: arr,
      tmdbId: tmdbId,
      tvdbId: tvdbId,
      connections: connections,
      name: name,
      light: light,
    ),
  );
}

/// The body of the add sheet, under its header: [showMediaAddSheet] opens it.
class MediaAddSheet extends ConsumerStatefulWidget {
  const MediaAddSheet({
    super.key,
    this.arr = ServiceKey.radarr,
    required this.tmdbId,
    this.tvdbId,
    required this.connections,
    required this.name,
    this.light,
  }) : assert(
         arr == ServiceKey.radarr ? tmdbId != null : (tmdbId ?? tvdbId) != null,
         'nothing to look the title up by',
       );

  /// Radarr for a film, Sonarr for a series.
  final ServiceKey arr;
  final int? tmdbId;

  /// A series' TVDB id, Sonarr's own; TMDB's stands in without it.
  final int? tvdbId;
  final List<ServiceInstance> connections;
  final String Function(ServiceInstance connection) name;
  final TitleLight? light;

  @override
  ConsumerState<MediaAddSheet> createState() => _MediaAddSheetState();
}

class _MediaAddSheetState extends ConsumerState<MediaAddSheet> {
  late ServiceInstance _to = widget.connections.first;

  bool get _series => widget.arr == ServiceKey.sonarr;

  ArrAddArgs get _args => (instanceId: _to.id, service: widget.arr);

  /// The title as the chosen connection looks it up.
  AsyncValue<Object> _lookup() => _series
      ? ref.watch(
          mediaSonarrAddLookupProvider((
            connectionId: _to.id,
            tvdbId: widget.tvdbId,
            tmdbId: widget.tmdbId,
          )),
        )
      : ref.watch(
          mediaAddLookupProvider((
            connectionId: _to.id,
            tmdbId: widget.tmdbId!,
          )),
        );

  void _lookAgain() => _series
      ? ref.invalidate(
          mediaSonarrAddLookupProvider((
            connectionId: _to.id,
            tvdbId: widget.tvdbId,
            tmdbId: widget.tmdbId,
          )),
        )
      : ref.invalidate(
          mediaAddLookupProvider((
            connectionId: _to.id,
            tmdbId: widget.tmdbId!,
          )),
        );

  Future<void> _pickMonitor(ArrAddFormState state) async {
    final picked = await showMediaValueSheet<SonarrMonitor>(
      context,
      title: 'Monitor',
      value: state.sonarrMonitor,
      currentLabel: state.sonarrMonitor.label,
      options: [
        for (final monitor in SonarrMonitor.values)
          MediaDetailValueOption(value: monitor, label: monitor.label),
      ],
    );
    if (picked != null) {
      ref
          .read(arrAddFormProvider(_args).notifier)
          .setSonarrMonitor(picked.value);
    }
  }

  Future<void> _pickType(SonarrSeriesType current) async {
    final picked = await showMediaValueSheet<SonarrSeriesType>(
      context,
      title: 'Series type',
      value: current,
      currentLabel: current.label,
      options: [
        for (final type in SonarrSeriesType.values)
          MediaDetailValueOption(value: type, label: type.label),
      ],
    );
    if (picked != null) {
      ref.read(arrAddFormProvider(_args).notifier).setSeriesType(picked.value);
    }
  }

  Future<void> _add(ArrAddFormNotifier form, ArrAddRequest request) async {
    final to = _to;
    final refused = await form.submit(request);
    if (refused == null && mounted) Navigator.of(context).pop(to);
  }

  Future<void> _pickProfile(ArrAddFormState state) async {
    final current = state.profiles.where((p) => p.id == state.profileId);
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: state.profileId,
      currentLabel: current.firstOrNull?.name ?? '',
      options: [
        for (final profile in state.profiles)
          MediaDetailValueOption(value: profile.id, label: profile.name),
      ],
    );
    if (picked != null) {
      ref.read(arrAddFormProvider(_args).notifier).selectProfile(picked.value);
    }
  }

  Future<void> _pickFolder(ArrAddFormState state) async {
    final picked = await showMediaValueSheet<String>(
      context,
      title: 'Root folder',
      value: state.rootFolder,
      currentLabel: state.rootFolder ?? '',
      options: [
        for (final folder in state.rootFolders)
          MediaDetailValueOption(value: folder, label: folder),
      ],
    );
    if (picked != null) {
      ref
          .read(arrAddFormProvider(_args).notifier)
          .selectRootFolder(picked.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final name = widget.name(_to);
    final state = ref.watch(arrAddFormProvider(_args));
    final form = ref.read(arrAddFormProvider(_args).notifier);
    final lookup = _lookup();
    final profile = state.profiles
        .where((p) => p.id == state.profileId)
        .firstOrNull
        ?.name;
    final monitor = state.monitored;
    final search = monitor && state.searchOnAdd;
    final indexers = switch (state.searchingIndexers) {
      null => 'your indexers',
      1 => 'your indexer',
      final count => 'your $count indexers',
    };
    final loaded = !state.isLoading && state.profiles.isNotEmpty;

    final Widget body = switch (lookup) {
      AsyncError(:final error) => InlineErrorRetry(
        message: 'Could not look it up in $name',
        error: error,
        service: widget.arr,
        instanceId: _to.id,
        onRetry: _lookAgain,
      ),
      _ when state.isLoading || lookup.isLoading => const ShimmerPlaceholder(
        height: 4 * 60,
      ),
      // The options did not load: the sentence the form wrote, and why.
      _ when !loaded => _Refusal(state: state),
      _ => MediaGroup(
        children: [
          MediaValueRow(
            label: 'Quality profile',
            value: Text(
              profile ?? '',
              textAlign: TextAlign.end,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            onTap: state.profiles.length > 1 ? () => _pickProfile(state) : null,
          ),
          MediaValueRow(
            label: 'Root folder',
            value: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  state.rootFolder ?? '',
                  textAlign: TextAlign.end,
                  style: AppType.mono.copyWith(color: room.inkSecondary),
                ),
                if (state.freeSpace[state.rootFolder] case final free?)
                  Text(
                    '${formatBytes(free)} free',
                    style: AppType.caption.copyWith(color: room.inkTertiary),
                  ),
              ],
            ),
            onTap: state.rootFolders.length > 1
                ? () => _pickFolder(state)
                : null,
          ),
          if (_series) ...[
            // Which episodes, in Sonarr's words, with what each means.
            MediaValueRow(
              label: 'Monitor',
              value: _Choice(
                label: state.sonarrMonitor.label,
                meaning: state.sonarrMonitor.meaning,
              ),
              onTap: () => _pickMonitor(state),
            ),
            if (lookup.value case final SonarrSeries series)
              () {
                final type =
                    state.seriesType ??
                    SonarrSeriesType.fromWire(series.seriesType) ??
                    SonarrSeriesType.standard;
                return MediaValueRow(
                  label: 'Series type',
                  value: _Choice(label: type.label, meaning: type.description),
                  onTap: () => _pickType(type),
                );
              }(),
          ] else
            MediaSwitchRow(
              label: 'Monitor',
              detail: monitor
                  ? 'Grabs it and upgrades it to ${profile ?? 'its profile'}'
                  : '$name lists it and never looks for it',
              value: monitor,
              onChanged: (value) {
                form.setMonitored(value);
                // Radarr does not search for a film it does not monitor.
                form.setSearchOnAdd(value);
              },
            ),
          MediaSwitchRow(
            label: 'Search when added',
            detail: !monitor
                ? (_series ? 'Needs episodes to monitor' : 'Needs Monitor on')
                : search
                ? 'Asks $indexers right away'
                : 'Search later from its page',
            value: search,
            onChanged: monitor ? form.setSearchOnAdd : null,
          ),
        ],
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.connections.length > 1) ...[
          Text(
            'Instance',
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectionPills<ServiceInstance>.wrap(
            values: widget.connections,
            selected: _to,
            labelBuilder: widget.name,
            onSelected: (connection) => setState(() => _to = connection),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        body,
        // A post that failed: its sentence, and why, over the button.
        if (loaded && state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Refusal(state: state),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: state.canSubmit && lookup.hasValue
              ? () => _add(form, switch (lookup.value!) {
                  final SonarrSeries series => SonarrAddRequest(
                    instanceId: _to.id,
                    series: series,
                  ),
                  final movie => RadarrAddRequest(
                    instanceId: _to.id,
                    movie: movie as RadarrMovie,
                  ),
                })
              : null,
          style: mediaLeadStyle(context, widget.light),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.isSubmitting)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.add_rounded, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(search ? 'Add and search' : 'Add to $name')),
            ],
          ),
        ),
      ],
    );
  }
}

/// A choice and what it means, right-aligned in its row: `Future episodes`,
/// `Only the ones that air from now` under it.
class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.meaning});

  final String label;
  final String meaning;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          textAlign: TextAlign.end,
          style: AppType.meta.copyWith(color: room.inkSecondary),
        ),
        Text(
          meaning,
          textAlign: TextAlign.end,
          style: AppType.caption.copyWith(color: room.inkTertiary),
        ),
      ],
    );
  }
}

/// What the form could not do: its sentence, and why under it.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.state});

  final ArrAddFormState state;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.error ?? '',
          // Amber unless the server did not answer: a refusal is a fault.
          style: AppType.row.copyWith(
            color: statusToneColor(
              Theme.of(context).colorScheme,
              surface: room.raised,
              switch (state.errorReason) {
                final reason? => failureTone(reason),
                null => StatusTone.warning,
              },
            ),
          ),
        ),
        if ((state.errorDetail ?? '').isNotEmpty)
          Text(
            state.errorDetail!,
            style: AppType.meta
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
      ],
    );
  }
}
