import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/release_list_widgets.dart';

/// A release row speaks one sentence and silences its parts (the design
/// contract): it was read pill by pill, a quality, a protocol and a score
/// with no title to hang them on.
void main() {
  testWidgets('a release row is one sentence, and Grab its own control', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              ReleaseListItem(
                release: const {
                  'title': 'Nosferatu.1922.1080p.BluRay.x264-GROUP',
                  'indexer': 'Indexer A',
                  'size': 4400000000,
                  'seeders': 42,
                  'leechers': 3,
                  'quality': {
                    'quality': {'name': 'Bluray-1080p'},
                  },
                  'ageMinutes': 4320,
                  'protocol': 'torrent',
                  'customFormatScore': 120,
                  'approved': true,
                },
                onGrab: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final row = find.bySemanticsLabel(
      RegExp(
        r'^Nosferatu\.1922\.1080p\.BluRay\.x264-GROUP\. Bluray-1080p, '
        r'Torrent, .+, Indexer A, 42 seeders, score \+120\. Approved\.$',
      ),
    );
    expect(row, findsOneWidget);
    expect(find.bySemanticsLabel('Torrent'), findsNothing);
    expect(find.bySemanticsLabel('Bluray-1080p'), findsNothing);
    handle.dispose();
  });
}
