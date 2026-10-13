import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
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

void main() {
  group('OnboardingWelcome', () {
    testWidgets('offers the one door and nothing to skip', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(OnboardingWelcome(onSetUp: () => opened++)),
      );

      expect(find.text(OnePunchline.claim), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text(SetupDoors.setUpHint), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      expect(find.textContaining('Skip'), findsNothing);

      await tester.tap(find.text('Set up a service'));
      expect(opened, 1);
    });

    testWidgets('shows Back only when there is somewhere to go back to', (
      tester,
    ) async {
      var back = 0;
      await tester.pumpWidget(
        _host(OnboardingWelcome(onSetUp: () {}, onBack: () => back++)),
      );

      await tester.tap(find.text('Back'));
      expect(back, 1);
    });

    testWidgets('the door speaks its hint on the button', (tester) async {
      // A hint wrapped around a button is dropped; it has to sit on the
      // label the button merges.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(OnboardingWelcome(onSetUp: () {})));

      expect(
        find.semantics.byLabel('Set up a service'),
        containsSemantics(
          isButton: true,
          hasTapAction: true,
          hint: SetupDoors.setUpHint,
        ),
      );
      handle.dispose();
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
