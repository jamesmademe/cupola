/// The requester's last drawings of her two shelves: Trending this week and
/// Coming soon, the posters Seerr's catalogue gave and what Seerr held of
/// each.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/media_preview_codec.dart';
import 'package:cupola/features/home/domain/home_module.dart';

/// How many posters a shelf keeps: what a rail shows of a page, and a margin.
/// The live shelf is as long as Seerr's page; the drawing is its first part,
/// and the rail grows to the right when the answer comes.
const _shelfKept = 20;

HomeLastKnownSlot<List<MediaPreview>> _shelf(HomeModule module, String id) =>
    HomeLastKnownSlot<List<MediaPreview>>(
      id: id,
      schema: 1,
      services: module.services.toSet(),
      // An empty answer is not a shelf: the drawing before it stays.
      encode: (items, _) => items.isEmpty
          ? null
          : {
              'items': [
                for (final item in items.take(_shelfKept))
                  mediaPreviewToJson(item),
              ],
            },
      decode: (data, _) {
        if (data is! Map || data['items'] is! List) return null;
        final items = <MediaPreview>[];
        for (final json in data['items'] as List) {
          final item = mediaPreviewFromJson(json);
          if (item == null) return null;
          items.add(item);
        }
        return items;
      },
    );

/// Trending this week as the requester's Home drew it.
final trendingLastKnown = _shelf(HomeModule.trending, 'trending');

/// Coming soon as the requester's Home drew it. Cut again when drawn
/// ([notYetOut]): a title whose day has passed since is not coming.
final comingSoonLastKnown = _shelf(HomeModule.comingSoon, 'coming_soon');

/// What of a last drawing of Coming soon is still not out on [today]: the
/// titles dated today or after, and the ones that name no day at all (nothing
/// says they came out).
List<MediaPreview> notYetOut(
  List<MediaPreview> drawn, {
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);
  bool stillComing(MediaPreview item) {
    final out = arrCalendarDate(item.releaseDate);
    return out == null || !out.isBefore(day);
  }

  return [
    for (final item in drawn)
      if (stillComing(item)) item,
  ];
}

/// A shelf as the requester's Home draws it: [items] for the carousel, and
/// [asOf] when it is the last drawing ([checking] while her Seerr is still
/// asked).
typedef HomeShelf = ({
  AsyncValue<List<MediaPreview>> items,
  DateTime? asOf,
  bool checking,
});

/// [read] as a shelf: the live titles, or until they come the last drawing's
/// ([cutAgain] first, for what is derived from a window).
///
/// A shelf is never replaced by a failure, nor dropped back to its skeleton
/// by a reload: it keeps the titles it has, and the Home's one line says the
/// server did not answer. A drawing with nothing left after it is cut again
/// is the skeleton, or nothing under a failure; and a shelf whose read failed
/// with nothing known is absent, as the line already says why.
HomeShelf homeShelfOf(
  HomeRead<List<MediaPreview>> read, {
  List<MediaPreview> Function(List<MediaPreview> drawn)? cutAgain,
}) {
  final failed = read.live.hasError;
  final value = read.value;
  AsyncValue<List<MediaPreview>> unknown() =>
      failed ? const AsyncData(<MediaPreview>[]) : const AsyncLoading();
  if (value == null) {
    return (items: unknown(), asOf: null, checking: !failed);
  }
  if (read.asOf == null) {
    return (items: AsyncData(value), asOf: null, checking: !failed);
  }
  final shown = cutAgain == null ? value : cutAgain(value);
  if (shown.isEmpty) return (items: unknown(), asOf: null, checking: !failed);
  return (items: AsyncData(shown), asOf: read.asOf, checking: !failed);
}
