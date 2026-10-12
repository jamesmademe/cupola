import 'package:flutter/material.dart';

import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';

/// Badge style (label, colour, icon) for a Prowlarr history [item].
///
/// Shared by the dashboard activity feed and the indexer detail history so
/// event styling stays consistent across both screens.
/// [colorScheme] is required because the two *status* arms: a refused query
/// and a successful grab are resolved through [statusToneColor] and therefore
/// walked against the surface. The remaining arms are not statuses: an RSS
/// sync is not "good": it is Prowlarr doing a Prowlarr thing, so they are the
/// secondary ink: the label says which event it was, and a hue per event type
/// was a legend with nothing to decode.
({String label, Color color, IconData icon}) prowlarrEventStyle(
  ProwlarrHistoryItem item,
  ColorScheme colorScheme,
) {
  if (!item.successful) {
    // A query the indexer refused is a fault the indexer reported, which is
    // amber. Red is kept for a Prowlarr that did not answer at all.
    return (
      label: 'Failed',
      color: statusToneColor(colorScheme, StatusTone.warning),
      icon: Icons.close_rounded,
    );
  }
  return switch (item.eventType) {
    'releaseGrabbed' => (
      label: 'Grab',
      color: statusToneColor(colorScheme, StatusTone.success),
      icon: Icons.download_rounded,
    ),
    'indexerQuery' => (
      label: 'Query',
      color: colorScheme.onSurfaceVariant,
      icon: Icons.search_rounded,
    ),
    'indexerRss' => (
      label: 'RSS',
      color: colorScheme.onSurfaceVariant,
      icon: Icons.rss_feed_rounded,
    ),
    // A *successful* auth handshake, because the `!item.successful` arm above
    // has already taken every failure. It was amber, which spent the fault
    // colour on an indexer doing exactly what it is supposed to, and left the
    // one real failure in this list indistinguishable from it.
    'indexerAuth' => (
      label: 'Auth',
      color: statusToneColor(colorScheme, StatusTone.info),
      icon: Icons.key_rounded,
    ),
    _ => (
      // Humanised, not uppercased: the badge is a dense label repeated on
      // every row, and the eyebrow is the only voice that uppercases.
      label: humanizeCamelCase(item.eventType ?? 'Event'),
      color: colorScheme.onSurfaceVariant,
      icon: Icons.bolt_rounded,
    ),
  };
}

/// The `source` field from a history [item]'s heterogeneous data map, or null
/// when it is missing or empty.
String? prowlarrHistorySource(ProwlarrHistoryItem item) {
  final source = item.data['source'];
  return (source is String && source.isNotEmpty) ? source : null;
}

/// A human-readable title for a history [item]: the search query when present,
/// otherwise a source-derived label, otherwise the raw event type.
String prowlarrHistoryTitle(ProwlarrHistoryItem item) {
  final query = item.data['query'];
  if (query is String && query.trim().isNotEmpty) return query;
  final source = prowlarrHistorySource(item);
  if (source != null) return '$source request';
  return item.eventType ?? 'Activity';
}

/// Formats an ISO-8601 timestamp as a coarse relative string (e.g. "5 min ago").
///
/// Uses a UTC wall clock (`DateTime.now()`); precision beyond minutes is not
/// needed for the activity feed.
String prowlarrRelativeTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final diff = DateTime.now().toUtc().difference(parsed.toUtc());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${withUnit(diff.inMinutes, 'min')} ago';
  if (diff.inHours < 24) return '${withUnit(diff.inHours, 'h')} ago';
  return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
}
