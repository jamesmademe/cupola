/// The first run behind a gateway: Connect's test meets Cloudflare Access, a
/// password prompt or a sign-in page before any connection is saved, and the
/// remedy is answered in the step, with the connection form's own Access row.
/// It never opens a form for a connection that does not exist yet.
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/onboarding_router.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/reel_finders.dart';

/// A first run (nothing saved) on [profile]'s network, on Connect for Radarr
/// with its address and key typed.
Future<(ProfileHarness, ProviderContainer)> _firstRunAtRadarr(
  WidgetTester tester,
  ConfigProfile profile, {
  String address = WorldHosts.radarr,
  Size viewport = const Size(800, 2400),
}) async {
  final harness = await ProfileHarness.start(profile);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
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
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await harness.settle(tester);
  await _tap(tester, harness, 'Set up a service');
  await _tap(tester, harness, 'Start with another service');
  // The list is longer than a phone's window: scrolled by its own scrollable,
  // so the pager is never asked to move.
  await tester.scrollUntilVisible(
    find.text('Set up Radarr'),
    100,
    scrollable: find
        .descendant(
          of: find.byType(OnboardingStart),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await _tap(tester, harness, 'Set up Radarr');
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), address);
  await tester.enterText(fields.at(1), worldKey(WorldIds.radarr));
  await harness.settle(tester);
  return (harness, container);
}

/// Taps [text] where it stands. No scrolling into view: the beat is a page
/// of a pager, and scrolling an enclosing scrollable would move the pager too.
Future<void> _tap(
  WidgetTester tester,
  ProfileHarness harness,
  String text,
) async {
  await tester.tap(find.text(text).first);
  await harness.settle(tester);
}

/// The step's own field labelled [label]: the walk's style, label above.
Finder _stepField(String label) => find.byWidgetPredicate(
  (widget) => widget is OnboardingField && widget.label == label,
);

/// The text input inside [_stepField].
Finder _field(String label) =>
    find.descendant(of: _stepField(label), matching: find.byType(TextField));

bool _selected(WidgetTester tester, String choice) =>
    tester
        .getSemantics(find.bySemanticsLabel(choice))
        .flagsCollection
        .isSelected ==
    Tristate.isTrue;

void main() {
  testWidgets('on a phone, a test meeting Cloudflare Access brings its verdict '
      'and its remedy into view above the pinned actions', (tester) async {
    // An iPhone 17 Pro, 402 by 874: the hero and the fields fill the screen,
    // and the verdict used to land under the pinned actions, found only by
    // scrolling.
    final (harness, _) = await _firstRunAtRadarr(
      tester,
      Profiles.p8,
      viewport: const Size(402, 874),
    );

    await tester.tap(find.text('Test connection').first);
    await harness.settle(tester);

    final remedy = find.text('Add a service token');
    expect(remedy, findsOneWidget);
    final pinnedTop = tester.getTopLeft(find.text('Test connection').last).dy;
    expect(tester.getBottomLeft(remedy).dy, lessThan(pinnedTop));
    expect(tester.getTopLeft(remedy).dy, greaterThan(0));
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('at ${width.round()}pt the step\'s Access choices are whole on '
        'screen', (tester) async {
      final (harness, _) = await _firstRunAtRadarr(
        tester,
        Profiles.p8,
        viewport: Size(width, 2400),
      );
      await _tap(tester, harness, 'Test connection');
      await _tap(tester, harness, 'Add a service token');

      for (final choice in const [
        'None',
        'Cloudflare Access',
        'Password',
        'Custom headers',
      ]) {
        final rect = tester.getRect(find.bySemanticsLabel(choice));
        expect(rect.left, greaterThanOrEqualTo(0), reason: choice);
        expect(rect.right, lessThanOrEqualTo(width), reason: choice);
        final label = tester.renderObject<RenderParagraph>(find.text(choice));
        expect(label.didExceedMaxLines, isFalse, reason: choice);
      }

      await harness.unmount(tester);
    });
  }

  testWidgets('Cloudflare Access at first run: the remedy opens the Access '
      'row in the step, and the walk saves Radarr with its token', (
    tester,
  ) async {
    final (harness, container) = await _firstRunAtRadarr(tester, Profiles.p8);

    await _tap(tester, harness, 'Test connection');
    expect(
      find.text(
        'Radarr is behind Cloudflare Access. Cupola needs a service token to '
        'reach it.',
      ),
      findsOneWidget,
    );
    // No Access row until the remedy asks for it.
    expect(_field('Client ID'), findsNothing);

    await _tap(tester, harness, 'Add a service token');
    // Answered here: still the walk's step, no connection form.
    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(findLine('Set up Radarr'), findsOneWidget);
    expect(_selected(tester, 'Cloudflare Access'), isTrue);
    // In the step's own style, as its address and key are, never the
    // connection form's outlined field with a floating label.
    expect(_stepField('Client ID'), findsOneWidget);
    expect(_stepField('Client secret'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText != null,
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _stepField('Client secret'),
        matching: find.byTooltip('Paste'),
      ),
      findsOneWidget,
    );

    await tester.enterText(_field('Client ID'), WorldTokens.radarr.id);
    await tester.enterText(_field('Client secret'), WorldTokens.radarr.secret);
    await _tap(tester, harness, 'Test connection');
    expect(
      find.text('Access let the token through and Radarr answered.'),
      findsOneWidget,
    );

    await _tap(tester, harness, 'Go to Home');
    final radarr = container
        .read(settingsProvider)
        .instanceById(WorldIds.radarr);
    expect(radarr?.url, WorldHosts.radarr);
    expect(radarr?.credential, worldKey(WorldIds.radarr));
    expect(radarr?.access, WorldTokens.radarr.access);

    await harness.unmount(tester);
  });

  testWidgets('a half-filled token in the step is caught under its field, '
      'in the step\'s style, and nothing is sent', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(tester, Profiles.p8);
    await _tap(tester, harness, 'Test connection');
    await _tap(tester, harness, 'Add a service token');
    final asked = harness.network.requestsTo(WorldIds.radarr).length;

    await tester.enterText(_field('Client ID'), WorldTokens.radarr.id);
    await _tap(tester, harness, 'Test connection');

    expect(
      find.descendant(
        of: _stepField('Client secret'),
        matching: find.text('Add the client secret'),
      ),
      findsOneWidget,
    );
    expect(harness.network.requestsTo(WorldIds.radarr), hasLength(asked));

    await harness.unmount(tester);
  });

  testWidgets('a password prompt at first run: an address typed with '
      'user:password@ becomes the proxy password, and the walk saves it', (
    tester,
  ) async {
    final (harness, container) = await _firstRunAtRadarr(
      tester,
      Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindPasswordPrompt(
          credentials: (username: 'matt', password: 'proxy-pw'),
        ),
      ),
      address: 'http://matt:proxy-pw@nas.home.arpa:7878',
    );
    // Accepted in the field: the test takes the credentials off it.
    expect(find.textContaining('Remove the username:password'), findsNothing);

    await _tap(tester, harness, 'Test connection');
    expect(find.text('Radarr answered.'), findsOneWidget);
    expect(_selected(tester, 'Password'), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      WorldHosts.radarr,
    );

    await _tap(tester, harness, 'Go to Home');
    final radarr = container
        .read(settingsProvider)
        .instanceById(WorldIds.radarr);
    expect(radarr?.url, WorldHosts.radarr);
    expect(
      radarr?.access,
      const ProxyPassword(username: 'matt', password: 'proxy-pw'),
    );

    await harness.unmount(tester);
  });

  testWidgets('a password prompt at first run, no password typed: Add the '
      'password opens the row on Password', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(
      tester,
      Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindPasswordPrompt(),
      ),
    );

    await _tap(tester, harness, 'Test connection');
    await _tap(tester, harness, 'Add the password');

    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(_selected(tester, 'Password'), isTrue);
    expect(_field('Proxy username'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a sign-in page at first run: Add access opens the row on '
      'Password, in the step', (tester) async {
    final (harness, _) = await _firstRunAtRadarr(
      tester,
      Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindSignInPage(),
      ),
    );

    await _tap(tester, harness, 'Test connection');
    expect(
      find.text(
        'Something in front of Radarr asks for a sign-in that Cupola cannot '
        'complete.',
      ),
      findsOneWidget,
    );
    await _tap(tester, harness, 'Add access');

    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(_selected(tester, 'Password'), isTrue);

    await harness.unmount(tester);
  });
}
