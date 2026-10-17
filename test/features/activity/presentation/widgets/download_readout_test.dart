/// The readout of a download's page keeps its height from the first reading
/// to the second. Seen live: the speed trace, drawn only at the second,
/// pushed Open and Stop down under a finger already on its way, and the tap
/// meant for Stop opened the client.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/activity/presentation/widgets/download_parts.dart';

final _opened = DateTime(2026, 10, 11, 9, 30);

Widget _readout(List<RateSample> trace) => MaterialApp(
  theme: AppTheme.darkTheme(),
  home: Scaffold(
    body: SizedBox(
      width: 370,
      child: DownloadReadout(
        stand: DownloadStand.downloading,
        percent: '0%',
        progress: 0,
        pace: '0\u00A0B/\u2060s',
        steps: const [],
        trace: trace,
        watched: const Duration(seconds: 5),
      ),
    ),
  ),
);

void main() {
  testWidgets('one reading or two, the same height', (tester) async {
    await tester.pumpWidget(_readout([(at: _opened, bytesPerSecond: 0)]));
    final first = tester.getSize(find.byType(DownloadReadout)).height;
    expect(find.text('since you opened this'), findsOneWidget);

    await tester.pumpWidget(
      _readout([
        (at: _opened, bytesPerSecond: 0),
        (at: _opened.add(const Duration(seconds: 5)), bytesPerSecond: 0),
      ]),
    );
    expect(tester.getSize(find.byType(DownloadReadout)).height, first);
  });
}
