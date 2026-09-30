/// The media-server slot on an arr page, through the app's real Jellyfin
/// client on the profiles' fake network: four nothings, four answers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_availability_slot.dart';

import '../../test_helpers/profiles/profiles.dart';

/// The slot's boxes, drawn in a column — the detail page's layout is not what
/// this is about.
class _Slot extends ConsumerWidget {
  const _Slot(this.title);

  final WorldTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = streamAvailabilitySlots(
      ref,
      accent: ServiceTheme.lamp,
      tmdbId: '${title.tmdbId}',
      kind: StreamItemKind.movie,
      title: title.title,
      year: title.year,
    );
    return Scaffold(
      body: Column(
        children: [
          for (final slot in slots) ...[Text('label:${slot.label}'), ?slot.box],
        ],
      ),
    );
  }
}

void main() {
  testWidgets('found: the card, as before', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const _Slot(WorldTitles.sintel),
    );

    expect(find.text('On ${ServiceKey.jellyfin.title}'), findsOneWidget);
    await harness.unmount(tester);
  });

  testWidgets('answered without it: "Not on Jellyfin", only after the answer', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const _Slot(WorldTitles.spriteFright),
    );

    expect(find.text('Not on Jellyfin'), findsOneWidget);
    expect(find.byType(FaultNote), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('did not answer: one quiet line, never "Not on Jellyfin"', (
    tester,
  ) async {
    // P7: Jellyfin does not answer.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p7,
      child: const _Slot(WorldTitles.spriteFright),
    );

    expect(
      find.text(
        'Jellyfin did not answer, so Cupola cannot say whether it has this.',
      ),
      findsOneWidget,
    );
    expect(find.byType(FaultNote), findsOneWidget);
    expect(find.textContaining('Not on'), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('not verified (case f): nothing at all', (tester) async {
    // P1's Jellyfin files Elephants Dream under another TMDB id.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const _Slot(WorldTitles.elephantsDream),
    );

    expect(find.textContaining('label:'), findsNothing);
    expect(find.textContaining('Not on'), findsNothing);
    await harness.unmount(tester);
  });

  testWidgets('not set up (case a): nothing, and nothing is asked', (
    tester,
  ) async {
    // P3 has no media server.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      child: const _Slot(WorldTitles.sintel),
    );

    expect(find.textContaining('label:'), findsNothing);
    expect(harness.network.requestsTo(WorldIds.jellyfin), isEmpty);
    await harness.unmount(tester);
  });
}
