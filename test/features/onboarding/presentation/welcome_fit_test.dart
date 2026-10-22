/// The Welcome at rest: the claim's whole sentence is above the doors, and
/// the doors are on the screen.
///
/// The doors are pinned under the claim and the claim scrolls above them, so
/// a sentence that does not fit slides under the doors and shows only after
/// the claim is scrolled. Measured with the app's own faces and each phone's
/// safe area: with Ahem, `flutter_test`'s default, text wraps onto more lines
/// than on a phone and the answer is for a screen that does not exist.
///
/// The doors' lines are drawn only where the sentence and they both fit
/// (`OnboardingWelcome.roomForDoorLines`); where they do not, each is still
/// said as its door's hint.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/setup_doors.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/app_fonts.dart';
import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/onboarding_router.dart';

/// A phone: its size, and the safe area the system takes off it.
typedef _Phone = ({String name, Size size, double top, double bottom});

const _phones = <_Phone>[
  (name: 'iPhone 17 Pro', size: Size(402, 874), top: 62, bottom: 34),
  (name: 'iPhone 15', size: Size(390, 844), top: 47, bottom: 34),
  (name: 'iPhone 17 Pro Max', size: Size(440, 956), top: 62, bottom: 34),
  (name: 'a 667pt phone', size: Size(390, 667), top: 20, bottom: 0),
];

/// The Welcome of a first run, on [phone], at [scale] times the reading size,
/// with or without the safe area.
Future<void> _pump(
  WidgetTester tester,
  _Phone phone, {
  double scale = 1,
  bool safeArea = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phone.size;
  final padding = FakeViewPadding(
    top: safeArea ? phone.top : 0,
    bottom: safeArea ? phone.bottom : 0,
  );
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWith((ref) => const SettingsModel()),
      initialOnboardingCompletedProvider.overrideWith((ref) => false),
    ],
  );
  addTearDown(container.dispose);
  final router = onboardingRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            // The ring's sweep never stops: settle on a still one.
            disableAnimations: true,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _body() => find.textContaining('Cupola talks straight');

Finder _lines() => find.text(SetupDoors.copyHint);

void _doorsAreOnTheScreen(WidgetTester tester, _Phone phone, bool safeArea) {
  final doors = tester.getRect(find.byType(SetupDoors));
  expect(doors.top, greaterThanOrEqualTo(safeArea ? phone.top : 0));
  expect(
    doors.bottom,
    lessThanOrEqualTo(phone.size.height - (safeArea ? phone.bottom : 0)),
  );
  for (final label in [
    'Set up a service',
    'Copy from another device',
    'I have a Seerr account',
  ]) {
    expect(
      tester.getRect(find.text(label)).bottom,
      lessThanOrEqualTo(phone.size.height),
      reason: label,
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  for (final phone in _phones) {
    group('on ${phone.name} (${phone.size.width.toInt()}x'
        '${phone.size.height.toInt()})', () {
      for (final safeArea in [true, false]) {
        testWidgets('at rest, the whole sentence is above the doors, '
            '${safeArea ? 'inside its safe area' : 'with no safe area'}', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          try {
            await _pump(tester, phone, safeArea: safeArea);

            expect(tester.takeException(), isNull);
            final body = tester.getRect(_body());
            final doors = tester.getRect(find.byType(SetupDoors));
            expect(
              body.bottom,
              lessThanOrEqualTo(doors.top),
              reason:
                  'the sentence ends at ${body.bottom}, the doors begin at '
                  '${doors.top}',
            );
            _doorsAreOnTheScreen(tester, phone, safeArea);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }

      for (final scale in [1.2, 1.4]) {
        testWidgets('at ${scale}x the sentence is still above the doors, '
            'whether or not their lines are drawn', (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          try {
            await _pump(tester, phone, scale: scale);

            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(_body()).bottom,
              lessThanOrEqualTo(tester.getRect(find.byType(SetupDoors)).top),
            );
            _doorsAreOnTheScreen(tester, phone, true);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }

      testWidgets('at twice the reading size the doors are pinned on the '
          'screen and their lines are not drawn; the claim may scroll', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await _pump(tester, phone, scale: 2);

          expect(tester.takeException(), isNull);
          expect(_lines(), findsNothing);
          _doorsAreOnTheScreen(tester, phone, true);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets('each line is said as its door\'s hint, drawn or not', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final handle = tester.ensureSemantics();
        try {
          await _pump(tester, phone);

          for (final (label, hint) in [
            ('Set up a service', SetupDoors.setUpHint),
            ('Copy from another device', SetupDoors.copyHint),
            ('I have a Seerr account', SetupDoors.signInHint),
          ]) {
            expect(
              find.semantics.byLabel(label),
              isSemantics(isButton: true, hasTapAction: true, hint: hint),
              reason: label,
            );
          }
        } finally {
          handle.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      });
    });
  }

  group('the lines under the doors', () {
    testWidgets('are drawn where the sentence and they both fit: a 440x956pt '
        'phone at rest', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await _pump(tester, _phones[2]);

        expect(_lines(), findsOneWidget);
        expect(find.text(SetupDoors.setUpHint), findsOneWidget);
        expect(find.text(SetupDoors.signInHint), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    for (final index in [0, 1, 3]) {
      final phone = _phones[index];
      testWidgets('are left out where they do not: ${phone.name}, inside its '
          'safe area', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await _pump(tester, phone);

          expect(_lines(), findsNothing);
          expect(find.text(SetupDoors.setUpHint), findsNothing);
          expect(find.text(SetupDoors.signInHint), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });
}
