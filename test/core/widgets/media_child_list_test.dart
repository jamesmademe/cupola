import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/media_child_list.dart';

void main() {
  testWidgets('a tile speaks its status word with the percent as a word', (
    tester,
  ) async {
    // The status word is drawn `Downloading 42%` and goes into the tile's
    // spoken sentence as it is drawn: a reader says "percent sign" or drops the
    // sign, so the sentence says the unit as a word.
    final handle = tester.ensureSemantics();
    const status = MediaStatusInfo(
      availability: MediaAvailability.missing,
      pipeline: MediaPipeline.downloading,
      progress: 0.42,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaChildTile.numbered(
            ordinal: 'E4',
            title: 'Pilot',
            facts: [mediaStatusWord(status)!],
            status: status,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Downloading 42%'), findsOneWidget);
    expect(
      find.semantics.byLabel('E4, Pilot, Downloading 42 percent'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
