import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/widgets/setup_doors.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The beats' own rules, tested on the widgets rather than through the whole
/// flow: what the Welcome offers and when it can go back, what the list of
/// services hands the screen when a row is chosen, and which of a field's two
/// lines a validation message may replace.
Widget _host(Widget child, {double width = 560}) => MaterialApp(
  theme: AppTheme.darkTheme(),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

/// The Welcome's claim: drawn on two lines, spoken as one sentence.
final _claim = find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == OnePunchline.claim,
);

void main() {
  group('OnboardingWelcome', () {
    testWidgets('offers the two doors and nothing to skip', (tester) async {
      var opened = 0;
      var signIn = 0;
      await tester.pumpWidget(
        _host(
          OnboardingWelcome(onSetUp: () => opened++, onSignIn: () => signIn++),
        ),
      );

      expect(_claim, findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(SetupDoors.setUpHint), findsOneWidget);
      expect(find.text(SetupDoors.signInHint), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      expect(find.textContaining('Skip'), findsNothing);

      await tester.tap(find.text('Set up a service'));
      expect(opened, 1);
      await tester.tap(find.text('I have a Seerr account'));
      expect(signIn, 1);
    });

    testWidgets('shows Back only when there is somewhere to go back to', (
      tester,
    ) async {
      var back = 0;
      await tester.pumpWidget(
        _host(
          OnboardingWelcome(
            onSetUp: () {},
            onSignIn: () {},
            onBack: () => back++,
          ),
        ),
      );

      await tester.tap(find.text('Back'));
      expect(back, 1);
    });

    testWidgets('says the claim once as the heading, and keeps the promise '
        'for the close', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(OnboardingWelcome(onSetUp: () {}, onSignIn: () {})),
      );

      expect(
        find.semantics.byLabel(OnePunchline.claim),
        containsSemantics(isHeader: true),
      );
      // Drawn on two lines, never spoken as two.
      expect(find.semantics.byLabel('A Cupola over'), findsNothing);
      expect(find.semantics.byLabel(OnePunchline.promise), findsNothing);
      handle.dispose();
    });

    testWidgets('the door speaks its hint on the button', (tester) async {
      // A hint wrapped around a button is dropped; it has to sit on the
      // label the button merges.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(OnboardingWelcome(onSetUp: () {}, onSignIn: () {})),
      );

      expect(
        find.semantics.byLabel('Set up a service'),
        containsSemantics(
          isButton: true,
          hasTapAction: true,
          hint: SetupDoors.setUpHint,
        ),
      );
      expect(
        find.semantics.byLabel('I have a Seerr account'),
        containsSemantics(
          isButton: true,
          hasTapAction: true,
          hint: SetupDoors.signInHint,
        ),
      );
      handle.dispose();
    });
  });

  group('OnboardingClose', () {
    Future<List<int>> pumpClose(
      WidgetTester tester, {
      required List<String> answering,
      List<String> notJoined = const [],
      Set<ServiceKey> setUp = const {},
    }) async {
      final entered = <int>[];
      await tester.pumpWidget(
        _host(
          OnboardingClose(
            answering: answering,
            notJoined: notJoined,
            setUp: setUp,
            onEnter: () async => entered.add(1),
          ),
        ),
      );
      return entered;
    }

    testWidgets('makes the promise when everything tried has joined', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final entered = await pumpClose(
        tester,
        answering: ['Seerr', 'Radarr', 'Sonarr'],
        setUp: {ServiceKey.seerr, ServiceKey.radarr, ServiceKey.sonarr},
      );

      expect(
        find.semantics.byLabel(OnePunchline.promise),
        containsSemantics(isHeader: true),
      );
      expect(
        find.text(
          'Seerr, Radarr and Sonarr are answering. Lidarr and the rest can be '
          'added any time from Connections in Settings.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Skip'), findsNothing);

      expect(
        find.semantics.byLabel('Enter Cupola'),
        containsSemantics(isButton: true),
      );
      await tester.tap(find.byType(ReelCommandButton));
      await tester.pump();
      expect(entered, [1]);
      handle.dispose();
    });

    testWidgets('counts instead of promising when something did not join', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpClose(
        tester,
        answering: ['Seerr', 'Radarr', 'Radarr 4K'],
        notJoined: ['Sonarr'],
        setUp: {ServiceKey.seerr, ServiceKey.radarr},
      );

      expect(find.semantics.byLabel(OnePunchline.promise), findsNothing);
      expect(find.text('3 of 4 answering.'), findsOneWidget);
      expect(
        find.text(
          'Seerr, Radarr and Radarr 4K are answering. Sonarr is not added '
          'yet: add it any time from Connections in Settings.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('never offers to add what is there, nor Readarr', (
      tester,
    ) async {
      await pumpClose(
        tester,
        answering: ['Lidarr'],
        setUp: {ServiceKey.lidarr},
      );
      expect(
        find.textContaining('Lidarr and the rest can be added'),
        findsNothing,
      );
      expect(find.textContaining('Readarr'), findsNothing);
      expect(
        find.textContaining('${ServiceKey.values.first.title} and the rest'),
        findsOneWidget,
      );
    });

    test('says names the way a sentence does', () {
      expect(OnboardingClose.sayNames(['Seerr']), 'Seerr');
      expect(OnboardingClose.sayNames(['Seerr', 'Radarr']), 'Seerr and Radarr');
      expect(
        OnboardingClose.sayNames(['Seerr', 'Radarr', 'Sonarr']),
        'Seerr, Radarr and Sonarr',
      );
      expect(
        OnboardingClose.sayNames([
          'Seerr',
          'Radarr',
          'Sonarr',
          'Lidarr',
          'Bazarr',
        ]),
        'Seerr, Radarr and 3 more',
      );
    });
  });

  group('OnboardingStart', () {
    Future<void> pumpStart(
      WidgetTester tester, {
      required ValueChanged<ServiceKey> onPick,
      VoidCallback? onBack,
    }) async {
      // Tall, so every row is on screen and a tap never has to scroll.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 3200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(OnboardingStart(onPick: onPick, onBack: onBack ?? () {})),
      );
    }

    testWidgets('hands the screen the service whose row was tapped', (
      tester,
    ) async {
      final picked = <ServiceKey>[];
      await pumpStart(tester, onPick: picked.add);

      await tester.tap(find.text('Seerr'));
      await tester.tap(find.text('Prowlarr'));
      await tester.tap(find.text('Set up Lidarr'));

      expect(picked, [
        ServiceKey.seerr,
        ServiceKey.prowlarr,
        ServiceKey.lidarr,
      ]);
    });

    testWidgets('puts the two that know the others first, and says what they '
        'know', (tester) async {
      await pumpStart(tester, onPick: (_) {});

      final rows = tester
          .widgetList<SettingsCard>(find.byType(SettingsCard))
          .map((row) => row.title)
          .toList();
      expect(rows.take(2), ['Seerr', 'Prowlarr']);
      expect(find.text(ServiceKey.seerr.knowsOthers!), findsOneWidget);
      expect(find.text(ServiceKey.prowlarr.knowsOthers!), findsOneWidget);
      // Every other row says what the service is for.
      expect(find.text(ServiceKey.radarr.role), findsOneWidget);
    });

    testWidgets('a service is listed once, however the registry groups it', (
      tester,
    ) async {
      await pumpStart(tester, onPick: (_) {});

      expect(
        find.byType(SettingsCard),
        findsNWidgets(ServiceKey.values.length),
      );
      // Seerr and Prowlarr are named in the first group and not again under
      // their domain.
      expect(find.text('Set up Seerr'), findsNothing);
      expect(find.text('Set up Prowlarr'), findsNothing);
    });

    testWidgets('Back is its own action', (tester) async {
      var back = 0;
      await pumpStart(tester, onPick: (_) {}, onBack: () => back++);

      await tester.tap(find.text('Back'));
      expect(back, 1);
    });
  });

  group('OnboardingField', () {
    testWidgets('a validation message joins the guidance rather than '
        'replacing it', (tester) async {
      // One slot held the breadcrumb, the steady note *and* the validation
      // result, so typing a bad address deleted the two lines that say how to
      // fix it. The breadcrumb moved up to the label row and the note stayed
      // put; only the validation line is new.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          OnboardingField(
            label: 'Address',
            controller: controller,
            isUrl: true,
            breadcrumb: 'Radarr → Settings → General',
            help: "Radarr's default port is 7878.",
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'http://not a host');
      await tester.pump();

      expect(find.text('Radarr → Settings → General'), findsOneWidget);
      expect(find.text("Radarr's default port is 7878."), findsOneWidget);
      // Whatever the validator's wording, there is a third line now, and it is
      // the one painted in the error tone.
      final notes = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (t) => t.style?.color == AppTheme.darkTheme().colorScheme.error,
          )
          .toList();
      expect(notes, isNotEmpty);
    });
  });
}
