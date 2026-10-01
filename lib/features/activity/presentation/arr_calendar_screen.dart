import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
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
/// One record is not always one row: a Radarr film carries its cinema, digital
/// and disc dates on the same record, and each one inside the window is a row
/// of its own, named ([arrCalendarEntries]).
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
                    service: widget.service,
                  ),
                ],
              );
            }

            final records = (snapshot.data ?? const <dynamic>[])
                .whereType<Map>()
                .map((record) => Map<String, dynamic>.from(record))
                .toList(growable: false);
            final entries = arrCalendarEntries(
              records,
              widget.service,
              windowStart: _windowStart,
              windowEnd: _windowEnd,
            );
            if (entries.isEmpty) {
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
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
              ),
              itemCount: entries.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) =>
                  _CalendarCard(service: widget.service, entry: entries[index]),
            );
          },
        ),
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.service, required this.entry});

  final ServiceKey service;
  final ArrCalendarEntry entry;

  @override
  Widget build(BuildContext context) {
    final record = entry.record;
    final day = entry.day;
    final date = day == null
        ? Lexicon.noFigure
        : formatIsoDate(day.toIso8601String());
    final title = arrCalendarTitle(entry, service);
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
              ).textTheme.labelMedium?.weight(FontWeight.w600),
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
                  ).textTheme.titleSmall?.weight(FontWeight.w600),
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
/// nested entity is what made every Sonarr row read `S5 E14 · Breaking Bad`
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
    // `Breaking Bad · S5 E14 · Ozymandias`: the show, where in it, then what
    // it is called. Any of the three can be missing without the row losing its
    // shape.
    return [?parent, ?_episodeCode(record), own ?? 'Episode'].join(' · ');
  }
  if (parent != null && own != null) return '$parent · $own';
  return own ?? parent ?? 'Scheduled item';
}

/// `S5 E14`, or null when either half is missing.
String? _episodeCode(Map<String, dynamic> record) => formatArrEpisodeCode(
  intOrNull(record['seasonNumber']),
  intOrNull(record['episodeNumber']),
);

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

/// One row of the calendar: a record, and the dated event that put it here.
@immutable
class ArrCalendarEntry {
  const ArrCalendarEntry({required this.record, this.day, this.event});

  final Map<String, dynamic> record;

  /// When, on the device's clock: a local calendar day for a release date, a
  /// local instant for an episode's airing. Null when the record carries no
  /// date this page can read; the row then says so with the em dash.
  final DateTime? day;

  /// Which of a film's dates this row is — `in cinemas`, `on digital`,
  /// `on disc` — or null for a record that has one date.
  final String? event;
}

/// A film's three dated events, in the order the board reads them.
const _radarrEvents = [
  ('inCinemas', Lexicon.inCinemas),
  ('digitalRelease', Lexicon.onDigital),
  ('physicalRelease', Lexicon.onDisc),
];

/// The calendar's rows, in date order: one per dated event in the window.
///
/// **A film is as many rows as it has dates in the window.** The *arr calendar
/// returns a film when *any* of its dates falls in the window, and the page
/// used to pick one — the first in the window — so a film out on digital today
/// and on disc in twelve days showed today's row and never the second. Each
/// date in the window is now its own row, named, and a film none of whose
/// dates lands inside (a server reading the window in its own timezone) keeps
/// one row on its first date rather than vanishing.
///
/// **A release date is a date, not an instant.** Radarr, Lidarr and Readarr
/// send `2026-10-12T00:00:00Z` for "12 October", and `.toLocal()` moved it to
/// the 11th anywhere west of Greenwich. Those are read as the calendar date
/// they spell. Sonarr's `airDateUtc` is a real instant — the episode airs at a
/// moment — and stays on the device's clock.
///
/// [windowStart] and [windowEnd] are local midnights, both days inclusive.
List<ArrCalendarEntry> arrCalendarEntries(
  List<Map<String, dynamic>> records,
  ServiceKey service, {
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  // A calendar day past the end, not `add(Duration(days: 1))`: a Duration is
  // absolute, and across a DST change it lands an hour off midnight.
  final endExclusive = DateTime(
    windowEnd.year,
    windowEnd.month,
    windowEnd.day + 1,
  );
  bool inWindow(DateTime day) =>
      !day.isBefore(windowStart) && day.isBefore(endExclusive);

  final entries = <ArrCalendarEntry>[];
  for (final record in records) {
    switch (service) {
      case ServiceKey.radarr:
        final dated = [
          for (final (field, event) in _radarrEvents)
            if (arrCalendarDate(record[field]) case final day?)
              ArrCalendarEntry(record: record, day: day, event: event),
        ];
        final shown = [
          for (final entry in dated)
            if (inWindow(entry.day!)) entry,
        ];
        if (shown.isNotEmpty) {
          entries.addAll(shown);
        } else if (dated.isNotEmpty) {
          entries.add(dated.first);
        } else {
          entries.add(
            ArrCalendarEntry(
              record: record,
              day: arrCalendarDate(record['releaseDate']),
            ),
          );
        }
      case ServiceKey.sonarr:
        final aired = DateTime.tryParse(
          record['airDateUtc']?.toString() ?? '',
        )?.toLocal();
        entries.add(
          ArrCalendarEntry(
            record: record,
            day: aired ?? arrCalendarDate(record['airDate']),
          ),
        );
      default:
        entries.add(
          ArrCalendarEntry(
            record: record,
            day:
                arrCalendarDate(record['releaseDate']) ??
                arrCalendarDate(record['airDate']),
          ),
        );
    }
  }

  // Date order, undated last; a tie keeps the server's order, which is why the
  // index is carried — `List.sort` is not stable.
  final indexed = entries.indexed.toList()
    ..sort((a, b) {
      final (aIndex, aEntry) = a;
      final (bIndex, bEntry) = b;
      final aDay = aEntry.day;
      final bDay = bEntry.day;
      if (aDay != null && bDay != null) {
        final byDay = aDay.compareTo(bDay);
        if (byDay != 0) return byDay;
      } else if (aDay != bDay) {
        return aDay == null ? 1 : -1;
      }
      return aIndex.compareTo(bIndex);
    });
  return [for (final (_, entry) in indexed) entry];
}

/// The row's name: the record's own, then the event when a film has several —
/// `Sprite Fright · on digital`.
String arrCalendarTitle(ArrCalendarEntry entry, ServiceKey service) {
  final title = _title(entry.record, service);
  final event = entry.event;
  return event == null ? title : '$title · $event';
}
