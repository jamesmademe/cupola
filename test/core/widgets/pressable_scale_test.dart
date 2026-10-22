import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/pressable_scale.dart';

void main() {
  testWidgets('a hint survives a control that cannot act', (tester) async {
    // The defect this guards: `hint: enabled ? semanticHint : null` dropped the
    // hint in the one state where a hint is load-bearing: a control the user
    // can see and cannot use. A screen reader landed on a named button with no
    // explanation of why it would not respond, while a sighted user read the
    // dimming for free. "requires qBittorrent" is exactly that sentence, and
    // the dimmed-but-tappable cell cannot exist without it.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PressableScale(
            semanticLabel: 'Open in qBittorrent',
            semanticHint: 'requires qBittorrent',
            child: SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(PressableScale)),
      isSemantics(label: 'Open in qBittorrent', hint: 'requires qBittorrent'),
    );
    handle.dispose();
  });

  testWidgets('a hint alone is enough to publish a node', (tester) async {
    // The cell is named by its own child text and carries only a hint, so
    // bailing out on a missing label would drop it entirely.
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PressableScale(
            semanticHint: 'requires qBittorrent',
            child: SizedBox(width: 48, height: 48),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(PressableScale)),
      isSemantics(hint: 'requires qBittorrent'),
    );
    handle.dispose();
  });
}
