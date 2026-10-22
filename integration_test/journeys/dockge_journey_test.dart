/// The stacks of Dockge, the family of I-01 to I-03.
///
/// The world: the `dockge-lab` scenario, which saves three compose files into
/// the lab's own `docker:dind` and measures whether that daemon can build a
/// container at all. This Mac's dind runs on a named volume now, so it can:
/// `cupola-log` runs and writes a line a second, `cupola-idle` was never
/// started, `cupola-crash` exited on its own.
///
/// What each journey proves, in the app's own words:
///
/// - **I-01**: the Stacks tab draws the three stacks with the status the
///   server reports; the stack page starts, stops, restarts and updates the
///   log stack, and takes it down. Every interruption asks first, with the
///   copy the list and the page share.
/// - **I-02**: a new stack is written and deployed, the editor saves an edit,
///   and a compose emptied by hand is refused before it reaches the server.
///   The journey deletes the stack it made; the lab's own three stay.
/// - **I-03**: the Terminal tab says it is a combined log, not a shell; the
///   log stack streams its line, and a stack that never ran waits for output.
///
/// The scenario is applied before the app opens and torn down after, so a
/// failed run does not leave the dind's stacks changed for the next one.
@Tags(['e2e'])
@Timeout(Duration(minutes: 15))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'testlab_journey_harness.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'I-01 · a stack started, stopped, restarted, updated and taken down',
    (tester) async {
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      final lab = Lab.load();
      await lab.command(['scenario', 'apply', 'dockge-lab']);
      addTearDown(() => lab.command(['scenario', 'teardown', 'dockge-lab']));
      final app = await LabApp.asOperator(
        tester,
        lab: lab,
        services: const {ServiceKey.dockge},
      );

      await app.go(tester, ServiceRoutes.dockgeStacks);
      await app.surface.see('cupola-log');
      await app.surface.see('cupola-idle');
      await app.surface.see('cupola-crash');
      // The statuses the scenario left: the log runs, the idle never started,
      // the crash exited.
      await app.surface.see('Running');
      expect(
        find.descendant(
          of: stackRow('cupola-log'),
          matching: find.text('Running'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stackRow('cupola-idle'),
          matching: find.text('Inactive'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: stackRow('cupola-crash'),
          matching: find.text('Stopped'),
        ),
        findsOneWidget,
      );

      // The page is the list row's destination, and it carries the verbs.
      await tester.tap(find.text('cupola-log'));
      await settle(tester, const Duration(seconds: 3));
      for (final verb in ['Start', 'Stop', 'Restart', 'Update', 'Down']) {
        await reveal(tester, verb);
        await app.surface.see(verb);
      }

      // Stop asks first, then says what it did.
      await reveal(tester, 'Stop');
      await tester.tap(find.text('Stop'));
      await settle(tester, const Duration(seconds: 1));
      await app.surface.see('Stop cupola-log?');
      await tester.tap(find.text('Stop stack'));
      await app.surface.see('Stopped cupola-log');

      // The list is the server's state, not the snackbar's promise.
      await tester.pageBack();
      await settle(tester, const Duration(seconds: 3));
      expect(
        find.descendant(
          of: stackRow('cupola-log'),
          matching: find.text('Stopped'),
        ),
        findsOneWidget,
        reason: 'the log stack should read Stopped',
      );

      // Start is additive and does not ask.
      await tester.tap(find.text('cupola-log'));
      await settle(tester, const Duration(seconds: 3));
      await reveal(tester, 'Start');
      await tester.tap(find.text('Start'));
      await app.surface.see('Started cupola-log');

      // Restart and Update confirm, then say what they did.
      for (final (verb, confirm, said) in [
        ('Restart', 'Restart stack', 'Restarted cupola-log'),
        ('Update', 'Update stack', 'Updated cupola-log'),
      ]) {
        await reveal(tester, verb);
        await tester.tap(find.text(verb));
        await settle(tester, const Duration(seconds: 1));
        await app.surface.see('$verb cupola-log?');
        await tester.tap(find.text(confirm));
        await app.surface.see(said);
      }

      // Down removes the containers, not the compose file.
      await reveal(tester, 'Down');
      await tester.tap(find.text('Down'));
      await settle(tester, const Duration(seconds: 1));
      await app.surface.see('Take cupola-log down?');
      await tester.tap(find.text('Take down'));
      await app.surface.see(
        'Stack cupola-log stopped and its containers removed',
      );

      await tester.pageBack();
      await settle(tester, const Duration(seconds: 3));
      expect(
        find.descendant(
          of: stackRow('cupola-log'),
          matching: find.text('Inactive'),
        ),
        findsOneWidget,
        reason: 'the log stack should read Inactive',
      );
    },
  );

  testWidgets('I-02 · a stack created, edited and deleted', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    const name = 'cupola-journey';
    final lab = Lab.load();
    // A failed run can leave the stack this journey made behind; clear it
    // before the scenario records what it found, so the next run does not meet
    // a stack that already exists.
    await deleteJourneyStackIfPresent(lab, name);
    await lab.command(['scenario', 'apply', 'dockge-lab']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'dockge-lab']));
    addTearDown(() => deleteJourneyStackIfPresent(lab, name));
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.dockge},
    );

    const compose =
        'services:\n'
        '  app:\n'
        '    image: cupola-lab/base:1\n'
        '    pull_policy: never\n'
        '    command: ["sleep", "infinity"]\n';

    await app.go(tester, ServiceRoutes.dockgeStacks);
    await app.surface.see('Stacks');
    await tester.tap(find.text('New'));
    await settle(tester, const Duration(seconds: 2));
    await app.surface.see('New stack');
    await app.surface.see('Stack name');
    await app.surface.see('compose.yaml');

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), name);
    await tester.enterText(fields.at(1), compose);
    await releaseFocus(tester);
    await reveal(tester, 'Deploy');
    await tester.tap(find.text('Deploy'));
    await app.surface.see(
      'Deployed $name',
      timeout: const Duration(minutes: 2),
    );
    await settle(tester, const Duration(milliseconds: 800));
    await app.surface.see(name);

    // The editor loads the real file and saves an edit. The stack is the
    // journey's own, and the delete at the end takes the edited file with it.
    await tester.tap(find.text(name));
    await settle(tester, const Duration(seconds: 3));
    await tester.tap(find.byTooltip('Edit compose'));
    await settle(tester, const Duration(seconds: 3));
    await app.surface.see('Edit $name');
    await tester.enterText(
      find.byType(TextField).first,
      '$compose# edited by the journey\n',
    );
    await releaseFocus(tester);
    await reveal(tester, 'Save');
    await tester.tap(find.text('Save'));
    await app.surface.see('Saved $name');

    // An emptied compose never reaches the server: the guard speaks before
    // the write, and the stack keeps its file.
    await tester.tap(find.byTooltip('Edit compose'));
    await settle(tester, const Duration(seconds: 3));
    await app.surface.see('Edit $name');
    await tester.enterText(find.byType(TextField).first, '   ');
    await releaseFocus(tester);
    await reveal(tester, 'Save');
    await tester.tap(find.text('Save'));
    await app.surface.see('compose.yaml is empty, that would wipe the stack');
    await tester.pageBack();
    await settle(tester, const Duration(seconds: 2));

    // Delete asks, confirms and removes the stack this journey made.
    await tester.tap(find.text('Delete stack'));
    await settle(tester, const Duration(seconds: 1));
    await app.surface.see('Delete $name?');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete stack'),
      ),
    );
    await app.surface.see('Deleted $name');
    await app.surface.unsee(name);
  });

  testWidgets('I-03 · the combined log and the action terminal', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final lab = Lab.load();
    await lab.command(['scenario', 'apply', 'dockge-lab']);
    addTearDown(() => lab.command(['scenario', 'teardown', 'dockge-lab']));
    final app = await LabApp.asOperator(
      tester,
      lab: lab,
      services: const {ServiceKey.dockge},
    );

    // The combined log only starts streaming after this client has acted on
    // the stack: Dockge builds the terminal on the action, not on the join.
    // The e2e's I-03 does the same, for the same reason.
    await app.go(tester, ServiceRoutes.dockgeStacks);
    await tester.tap(find.text('cupola-log'));
    await settle(tester, const Duration(seconds: 3));
    await reveal(tester, 'Start');
    await tester.tap(find.text('Start'));
    await app.surface.see('Started cupola-log');

    await app.go(tester, ServiceRoutes.dockgeTerminal);
    await app.surface.see('Choose a stack');
    await app.surface.seePart('not an interactive shell');

    await tapPill(tester, 'cupola-log');
    await settle(tester, const Duration(seconds: 2));
    await app.surface.seePart('combined log');
    await app.surface.seePart('cupola-log line');

    // A stack that never ran has nothing to stream: the pane says so
    // instead of inventing a log.
    await tapPill(tester, 'cupola-idle');
    await settle(tester, const Duration(seconds: 3));
    await app.surface.seePart('Waiting for output');
  });
}

/// The Stacks list row for [name].
Finder stackRow(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;

/// Taps a pill in the terminal's picker, scrolling the row right when the
/// stack sits past the edge (the row is wider than a 390pt phone).
Future<void> tapPill(WidgetTester tester, String label) async {
  final pill = find.text(label);
  await tester.ensureVisible(pill);
  await settle(tester, const Duration(milliseconds: 400));
  await tester.tap(pill);
}

/// Drops the field's focus so its caret does not pull the scroll position back
/// over the footer button while the keyboard inset settles.
Future<void> releaseFocus(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester, const Duration(milliseconds: 500));
}

/// Brings [text] into view, building it first when the list has not reached it.
Future<void> reveal(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      finder,
      find.byType(ListView).last,
      const Offset(0, -320),
    );
  }
  await tester.ensureVisible(finder);
  await settle(tester, const Duration(milliseconds: 400));
}

/// Removes the stack I-02 creates, when a run stopped before its own delete.
///
/// The `dockge-lab` scenario owns three stacks and puts them back; this one
/// belongs to the journey. It is cleaned before the scenario records the world
/// it found, and again when the test ends.
Future<void> deleteJourneyStackIfPresent(Lab lab, String name) async {
  final connection = lab.connectionOf(ServiceKey.dockge);
  final client = DockgeClient(
    baseUrl: connection.url,
    username: connection.username,
    password: connection.credential,
    idleTimeout: const Duration(seconds: 20),
  );
  try {
    await client.ensureConnected();

    Future<List<DockgeStack>> read() async {
      final list = client.stackListStream.first;
      await client.requestStackList();
      return list.timeout(const Duration(seconds: 10));
    }

    if (!(await read()).any((stack) => stack.name == name)) return;
    try {
      await client.stopStack(name);
    } on Object {
      // A stack that is already down has nothing to stop; deleting it is the
      // step that has to hold.
    }
    await client.deleteStack(name);
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!(await read()).any((stack) => stack.name == name)) return;
    }
    fail('the journey stack $name is still listed after its delete');
  } finally {
    client.close();
  }
}
