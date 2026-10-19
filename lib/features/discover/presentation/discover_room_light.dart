import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The pictures Discover may take its light from, in order of preference: the
/// poster at the end of the band's line (the next thing out), then the
/// Trending door's three. Public pictures only: a picture behind a key is not
/// read for a light. Null while a source the room waits for is still being
/// read, so the room chooses once, not as each source answers.
final discoverRoomSourcesProvider = Provider.autoDispose<List<String>?>((ref) {
  final sources = <String>[];
  if (ref.watch(hasCalendarProvider)) {
    final calendar = ref.watch(calendarProvider);
    if (!calendar.hasValue && !calendar.hasError) return null;
    if (calendar.value?.events case final events?) {
      final now = ref.watch(calendarClockProvider)();
      final poster = CalendarDigest.of(events, now).lead?.poster;
      if (poster != null && poster.headers == null && poster.url.isNotEmpty) {
        sources.add(poster.url);
      }
    }
  }
  // Checked before Trending is watched: it throws without a Seerr to ask.
  final seerr = ref.watch(
    activeInstanceProvider(
      ServiceKey.seerr,
    ).select((instance) => instance?.isConfigured ?? false),
  );
  if (seerr) {
    final trending = ref.watch(atriumTrendingProvider);
    if (!trending.hasValue && !trending.hasError) return null;
    final door = trendingDoorPictures(trending.value ?? const []);
    sources.addAll([?door.light, ...door.posters]);
  }
  return sources;
});

/// Discover's light: the most coloured of its pictures
/// ([discoverRoomSourcesProvider]), so a dark next release does not leave the
/// room grey while Trending holds colour; null for the lamp.
final discoverRoomLightProvider = Provider.autoDispose<TitleLight?>((ref) {
  final sources = ref.watch(discoverRoomSourcesProvider);
  if (sources == null || sources.isEmpty) return null;
  return mostColouredTitleLight(ref, sources);
});
