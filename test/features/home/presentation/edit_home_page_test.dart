import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/edit_home_page.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// Edit Home: reorder by handle or arrows, switch off, reset, and the moves a
/// screen reader is offered.
void main() {
  late SharedPreferences prefs;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Audience audience = Audience.operator,
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    prefs = await SharedPreferences.getInstance();
    // Tall enough for the whole page: a list builds only what it shows.
    tester.view.physicalSize = const Size(1206, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        shellAudienceProvider.overrideWith(() => _Fixed(audience)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const EditHomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('lists Needs you locked, the ordered modules, then Set up '
      'next, with Reset dimmed on the default', (tester) async {
    await pump(tester);

    for (final module in HomeModule.of(Audience.operator)) {
      expect(find.text(module.label), findsOneWidget, reason: module.label);
    }
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    // Needs you has no switch; the seven ordered modules and Set up next do.
    expect(find.byType(Switch), findsNWidgets(8));
    final reset = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(reset.onPressed, isNull);
    // The other person's default, from the registry.
    expect(
      find.textContaining('Trending this week and Coming soon'),
      findsOneWidget,
    );
  });

  testWidgets('a tapped handle lifts its row; the arrows move it and the '
      'layout is kept', (tester) async {
    final container = await pump(tester);

    await tester.tap(find.bySemanticsLabel('Move Arrived'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Move Arrived up'), findsOneWidget);
    expect(find.bySemanticsLabel('Move Arrived down'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Move Arrived down'));
    await tester.pumpAndSettle();

    expect(container.read(homeLayoutProvider).order, [
      HomeModule.featured,
      HomeModule.continueWatching,
      HomeModule.comingUp,
      HomeModule.downloads,
      HomeModule.arrived,
      HomeModule.requests,
      HomeModule.nowPlaying,
    ]);
    final saved = HomeLayout.read(
      prefs.getString('home_layout_operator'),
      Audience.operator,
    );
    expect(saved.order, container.read(homeLayoutProvider).order);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(
      tester.getTopLeft(find.text('Downloads')).dy,
      lessThan(tester.getTopLeft(find.text('Arrived')).dy),
    );
  });

  testWidgets('a switch takes a module off the Home, and Reset brings the '
      'default back', (tester) async {
    final container = await pump(tester);

    // Featured, Continue watching, Coming up, Arrived, Downloads, then
    // Requests.
    await tester.tap(find.byType(Switch).at(5));
    await tester.pumpAndSettle();
    expect(
      container.read(homeLayoutProvider).isOn(HomeModule.requests),
      isFalse,
    );
    expect(prefs.getString('home_layout_operator'), contains('requests'));

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(container.read(homeLayoutProvider).isDefault, isTrue);
    expect(prefs.getString('home_layout_operator'), isNull);
  });

  testWidgets('a screen reader can move a row from its switch', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pump(tester);

    final node = tester.getSemantics(
      find.descendant(
        of: find
            .ancestor(of: find.text('Downloads'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      ),
    );
    final actions = node.getSemanticsData().customSemanticsActionIds!;
    expect(actions, hasLength(2));
    final ids = {
      for (final id in actions) CustomSemanticsAction.getAction(id)!.label: id,
    };
    expect(ids.keys, containsAll(['Move up', 'Move down']));

    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      ids['Move up'],
    );
    await tester.pumpAndSettle();
    expect(container.read(homeLayoutProvider).order.take(5), [
      HomeModule.featured,
      HomeModule.continueWatching,
      HomeModule.comingUp,
      HomeModule.downloads,
      HomeModule.arrived,
    ]);
    handle.dispose();
  });

  testWidgets('the requester arranges her own Home, kept apart', (
    tester,
  ) async {
    final container = await pump(
      tester,
      audience: Audience.requester,
      stored: {
        'home_layout_operator': HomeLayout.defaultFor(
          Audience.operator,
        ).switched(HomeModule.requests, on: false).toJson(),
      },
    );

    expect(find.text('Trending this week'), findsOneWidget);
    expect(find.text('Needs you'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(container.read(homeLayoutProvider).isDefault, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(prefs.getString('home_layout_requester'), contains('trending'));
    expect(prefs.getString('home_layout_operator'), contains('requests'));
  });
}

class _Fixed extends ShellAudienceNotifier {
  _Fixed(this.audience);

  final Audience audience;

  @override
  Audience build() => audience;
}
