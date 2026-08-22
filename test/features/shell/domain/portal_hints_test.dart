import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';

Future<ProviderContainer> _container({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hints are on by default and the demo is pending', () async {
    final container = await _container();
    final state = container.read(portalHintsProvider);

    expect(state.enabled, isTrue);
    expect(state.demoBouncePending, isTrue);
    expect(state.coachVisible, isFalse);
  });

  test('the coach × turns the Portal hints off, and persists', () async {
    final container = await _container();
    container.read(portalHintsProvider.notifier).setEnabled(false);

    expect(container.read(portalHintsProvider).enabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('portal_hints_enabled'), isFalse);
  });

  test('the Settings switch turns them back on, and replays the lesson whole',
      () async {
    final container = await _container(
      initial: {'portal_hints_enabled': false, 'portal_hint_demo_shown': true},
    );
    expect(container.read(portalHintsProvider).enabled, isFalse);
    expect(container.read(portalHintsProvider).demoBouncePending, isFalse);

    container.read(portalHintsProvider.notifier).setEnabled(true);

    final state = container.read(portalHintsProvider);
    expect(state.enabled, isTrue);
    // Re-enabling re-arms the one-shot: the demo plays again, not just the tip.
    expect(state.demoBouncePending, isTrue);
  });

  test('the demo is one-shot while the switch stays on', () async {
    final container = await _container();
    final notifier = container.read(portalHintsProvider.notifier);

    notifier.markDemoShown();
    expect(container.read(portalHintsProvider).demoBouncePending, isFalse);

    notifier.markDemoShown();
    expect(container.read(portalHintsProvider).demoBouncePending, isFalse);
  });

  test('three manual journeys summon the coach; using the Portal resets it',
      () async {
    final container = await _container();
    final notifier = container.read(portalHintsProvider.notifier);

    notifier.noteManualJourney();
    notifier.noteManualJourney();
    expect(container.read(portalHintsProvider).coachVisible, isFalse);

    notifier.noteManualJourney();
    expect(container.read(portalHintsProvider).coachVisible, isTrue);

    notifier.notePortalUsed();
    expect(container.read(portalHintsProvider).coachVisible, isFalse);
    expect(container.read(portalHintsProvider).manualJourneys, 0);
  });

  test('switched off, no number of journeys brings the coach back', () async {
    final container = await _container(
      initial: {'portal_hints_enabled': false, 'portal_manual_journeys': 9},
    );
    expect(container.read(portalHintsProvider).coachVisible, isFalse);
  });
}
