/// The lens sheet says whether each connection answers.
///
/// The sheet is where the user points the whole app at one connection, and
/// it listed each by name and address only: moving the lens onto a server
/// that did not answer looked exactly like moving it onto one that did. Each
/// row now carries the probe's own answer for its connection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  testWidgets('P1, the 4K dark: the sheet says which Radarr answers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.radarr4k,
        ConnectionBehaviour.didNotAnswer,
      ),
      child: const Scaffold(
        body: Center(child: InstanceLensBadge(service: ServiceKey.radarr)),
      ),
    );

    await tester.tap(find.byType(InstanceLensBadge));
    await harness.settle(tester);

    // The one that answers: its address, under a glyph that says so aloud.
    expect(find.text('nas.home.arpa:7878'), findsOne);
    expect(
      find.bySemanticsLabel('Radarr 1, Answering, nas.home.arpa:7878'),
      findsOne,
    );
    // The one that did not: the cause in words, ahead of its address, said
    // once.
    expect(find.text('Did not answer · nas.home.arpa:7879'), findsOne);
    expect(
      find.bySemanticsLabel('4K, Did not answer, nas.home.arpa:7879'),
      findsOne,
    );
    expect(find.byIcon(Icons.cloud_off_rounded), findsOne);

    handle.dispose();
    await harness.unmount(tester);
  });
}
