import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Calendar body shared by the four *arr services.
///
/// The endpoint is intentionally kept as raw maps: the record is a movie,
/// episode, album or book depending on the service, while this surface only
/// promises a dated release and a useful title. Missing fields stay absent
/// rather than becoming a fabricated date or a zero count.
///
/// The window is thirty days from local midnight, and the request sends that
/// **local** date deliberately. A user asking for "the next thirty days"
/// means their thirty days; the server then reads the bare date in its own
/// timezone, and there is no third place to stand — converting to UTC first
/// would move the boundary for everyone east of Greenwich to be wrong in the
/// other direction.
class ArrCalendarScreen extends ConsumerStatefulWidget {
  const ArrCalendarScreen({
    super.key,
    required this.service,
    this.topPadding = 0,
  });

  final ServiceKey service;
  final double topPadding;

  @override
  ConsumerState<ArrCalendarScreen> createState() => _ArrCalendarScreenState();
}

class _ArrCalendarScreenState extends ConsumerState<ArrCalendarScreen> {
  Future<List<dynamic>>? _future;

  /// The window the request asked for, kept so a card can say which of a
  /// record's several dates is the one that put it on this page.
  DateTime _windowStart = DateTime.now();
  DateTime _windowEnd = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (ref.read(currentSettingsProvider).isServiceConfigured(widget.service)) {
      _future = _load();
    }
  }

  Future<List<dynamic>> _load() {
    final now = DateTime.now();
    _windowStart = DateTime(now.year, now.month, now.day);
    _windowEnd = DateTime(now.year, now.month, now.day + 30);
    final service = switch (widget.service) {
      ServiceKey.radarr => ref.read(radarrServiceProvider),
      ServiceKey.sonarr => ref.read(sonarrServiceProvider),
      ServiceKey.lidarr => ref.read(lidarrServiceProvider),
      ServiceKey.readarr => ref.read(readarrServiceProvider),
      _ => throw UnsupportedError(
        '${widget.service.name} has no calendar endpoint',
      ),
    };
    return service.getCalendar(start: now, end: _windowEnd);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(widget.service);
    if (!configured) {
      return NotConfiguredPlaceholder.forService(widget.service);
    }

    // The request is held in state, so moving the instance lens would
    // otherwise leave the previous server's calendar on screen under the new
    // connection's label. Re-issuing it is the only way the page can tell the
    // truth about which server it is showing.
    ref.listen(activeInstanceProvider(widget.service), (previous, next) {
      if (previous?.id == next?.id) return;
      _reload();
    });

    final future = _future ??= _load();
    return AmbientScaffold(
      accent: widget.service.accent,
      body: RefreshIndicator(
        // Awaited, not fired and forgotten: `_reload` is synchronous, so
        // returning straight from it snapped the spinner away before the new
        // request had left the device.
        onRefresh: () async {
          _reload();
          await _future;
        },
        child: FutureBuilder<List<dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: widget.topPadding),
                children: [AppSkeleton.listRows(count: 6)],
              );
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: widget.topPadding),
                children: [
                  AppErrorState(
                    error: snapshot.error!,
                    onRetry: _reload,
                    serviceName: widget.service.title,
                  ),
                ],
              );
            }

            final records = (snapshot.data ?? const <dynamic>[])
                .whereType<Map>()
                .map((record) => Map<String, dynamic>.from(record))
                .toList(growable: false);
            if (records.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: widget.topPadding),
                children: const [
                  AppEmptyState(
                    icon: Icons.calendar_month_rounded,
                    title: 'Nothing scheduled',
                    message: 'The next 30 days are clear on this service.',
                  ),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                widget.topPadding + AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              itemCount: records.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _CalendarCard(
                service: widget.service,
                record: records[index],
                windowStart: _windowStart,
                windowEnd: _windowEnd,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.service,
    required this.record,
    required this.windowStart,
    required this.windowEnd,
  });

  final ServiceKey service;
  final Map<String, dynamic> record;
  final DateTime windowStart;
  final DateTime windowEnd;

  @override
  Widget build(BuildContext context) {
    final date = _date(record, service, windowStart, windowEnd);
    final title = _title(record, service);
    final subtitle = _subtitle(record, service);
    return AppCard.outlined(
      borderColor: Theme.of(context).colorScheme.outlineVariant,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: service.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              date,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.weight(FontWeight.w700),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.weight(FontWeight.w700),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The name of the thing this row is about.
///
/// **The calendar record *is* the dated entity for all four services** — a
/// movie, an episode, an album, a book. What the `include*` parameters embed is
/// its *parent*, never itself. Reading `record['series']` as though it were the
/// nested entity is what made every Sonarr row read `S05E14 · Breaking Bad`
/// and never name the episode at all; there is no nested-entity lookup here any
/// more because there was never one to make.
String _title(Map<String, dynamic> record, ServiceKey service) {
  final own = stringOrNull(
    record['title'] ?? record['name'] ?? record['sourceTitle'],
  );
  final parent = switch (service) {
    ServiceKey.sonarr => stringOrNull(mapOrNull(record['series'])?['title']),
    ServiceKey.lidarr => stringOrNull(
      mapOrNull(record['artist'])?['artistName'],
    ),
    ServiceKey.readarr => stringOrNull(
      mapOrNull(record['author'])?['authorName'],
    ),
    _ => null,
  };

  if (service == ServiceKey.sonarr) {
    // `Breaking Bad · S05E14 · Ozymandias`: the show, where in it, then what
    // it is called. Any of the three can be missing without the row losing its
    // shape.
    return [?parent, ?_episodeCode(record), own ?? 'Episode'].join(' · ');
  }
  if (parent != null && own != null) return '$parent · $own';
  return own ?? parent ?? 'Scheduled item';
}

/// `S05E14`, or null when either half is missing.
String? _episodeCode(Map<String, dynamic> record) {
  final season = intOrNull(record['seasonNumber']);
  final episode = intOrNull(record['episodeNumber']);
  if (season == null || episode == null) return null;
  return 'S${season.toString().padLeft(2, '0')}'
      'E${episode.toString().padLeft(2, '0')}';
}

String? _subtitle(Map<String, dynamic> record, ServiceKey service) {
  final parts = <String>[
    ?stringOrNull(record['status']),
    if (record['monitored'] case final bool monitored)
      monitored ? 'Monitored' : 'Not monitored',
    // The air *time*, since the chip beside it already carries the day. The
    // raw `airDateUtc` used to be pasted in whole, which put a machine-shaped
    // `2026-09-21T01:00:00Z` in a line of prose.
    if (service == ServiceKey.sonarr) ?_airTime(record),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Local wall-clock time of an episode's airing, to the minute.
String? _airTime(Map<String, dynamic> record) {
  final parsed = DateTime.tryParse(
    record['airDateUtc']?.toString() ?? '',
  )?.toLocal();
  if (parsed == null) return null;
  return '${parsed.hour.toString().padLeft(2, '0')}:'
      '${parsed.minute.toString().padLeft(2, '0')}';
}

/// The date that put this record on this page.
///
/// A film has up to four, and the *arr calendar returns it when **any** of
/// them falls in the window — so preferring `inCinemas` unconditionally put a
/// 2023 cinema date on a page titled "the next 30 days" for a film whose
/// digital release is next week. The candidates are tried in the order the
/// board reads them, but a candidate inside the window always wins over one
/// outside it.
String _date(
  Map<String, dynamic> record,
  ServiceKey service,
  DateTime windowStart,
  DateTime windowEnd,
) {
  final candidates = switch (service) {
    ServiceKey.radarr => [
      record['inCinemas'],
      record['digitalRelease'],
      record['physicalRelease'],
      record['releaseDate'],
    ],
    ServiceKey.sonarr => [record['airDateUtc'], record['airDate']],
    _ => [record['releaseDate'], record['airDate']],
  };

  final parsed = candidates
      .map((raw) => DateTime.tryParse(raw?.toString() ?? '')?.toLocal())
      .whereType<DateTime>()
      .toList(growable: false);
  if (parsed.isEmpty) return '—';

  final inWindow = parsed.firstWhere(
    (date) =>
        !date.isBefore(windowStart) &&
        date.isBefore(windowEnd.add(const Duration(days: 1))),
    orElse: () => parsed.first,
  );
  return formatIsoDate(inWindow.toIso8601String());
}
