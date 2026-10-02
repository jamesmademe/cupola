/// The viewer picker tells a server with no users from one that did not
/// answer.
///
/// `getViewers` turned every failure into an empty list, so a Jellyfin that
/// was down read "This server reports no users.", a claim about a server
/// nobody could ask. A failure now reads as a failure, in the
/// classification's words, and the empty line is only ever an answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/stream/presentation/widgets/jellyfin_viewer_picker.dart';

import '../../test_helpers/profiles/profiles.dart';

const _noUsers = 'This server reports no users.';

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileNetwork network)? before,
}) async {
  final harness = await ProfileHarness.start(profile);
  before?.call(harness.network);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const Scaffold(
          body: JellyfinViewerPicker(instanceId: WorldIds.jellyfin),
        ),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

void main() {
  testWidgets('a Jellyfin that did not answer says so, never that it has no '
      'users', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.jellyfin,
        ConnectionBehaviour.didNotAnswer,
      ),
    );

    expect(find.text(_noUsers), findsNothing);
    expect(
      find.text('Jellyfin did not answer, so its viewers are not shown.'),
      findsOneWidget,
    );
    await harness.unmount(tester);
  });

  testWidgets('a Jellyfin that answers with no users says it has none', (
    tester,
  ) async {
    final harness = await _pump(
      tester,
      Profiles.p1,
      before: (network) => network.on(
        WorldIds.jellyfin,
        'GET',
        '/Users',
        (_) => NetworkReply.json(const <Object?>[]),
      ),
    );

    expect(find.text(_noUsers), findsOneWidget);
    await harness.unmount(tester);
  });

  testWidgets('a Jellyfin that answers lists its people', (tester) async {
    final harness = await _pump(tester, Profiles.p1);

    expect(find.widgetWithText(ChoiceChip, WorldPeople.anna), findsOneWidget);
    expect(find.text(_noUsers), findsNothing);
    await harness.unmount(tester);
  });
}
