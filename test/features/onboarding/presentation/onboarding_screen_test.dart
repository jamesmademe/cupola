import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/widgets/setup_doors.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_walk.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/onboarding_router.dart';
import '../../../test_helpers/reel_finders.dart';
import '../../../test_helpers/settings_scope.dart';

/// The way in is the Welcome, then Connect for one service, so its length does
/// not depend on the user: one door, one form. Every case here was a real
/// defect in the flows this replaced, and the scenarios that still exist are
/// kept; what answers a test (a service that says yes) lives in
/// `onboarding_flow_test.dart`, where the network is faked.
void main() {
  group('the Welcome', () {
    testWidgets('makes its claim and has one door', (tester) async {
      await _pumpOnboarding(tester);

      expect(find.text(OnePunchline.claim), findsOneWidget);
      expect(_button('Set up a service'), findsOneWidget);
      // What the door leads with, said under it so the button stays a verb.
      expect(find.text(SetupDoors.setUpHint), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('a first run has nothing to go back to', (tester) async {
      await _pumpOnboarding(tester);

      expect(find.text('Back'), findsNothing);
    });

    testWidgets('has no Skip, and neither does Connect', (tester) async {
      // A way in that can be skipped is a way in that opens an empty app: with
      // nothing set up there is nothing for the shell to show.
      await _pumpOnboarding(tester);
      expect(_skips(), findsNothing);

      await _tap(tester, 'Set up a service');
      expect(_skips(), findsNothing);

      await _tap(tester, 'Start with another service');
      expect(_skips(), findsNothing);

      await _tap(tester, 'Set up Sonarr');
      expect(_skips(), findsNothing);
    });

    testWidgets('the door opens Connect on Seerr', (tester) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up a service');

      // The headline names the service, the eyebrow says there is a second
      // step after it, and the lead says why to start here.
      expect(findLine('Set up Seerr'), findsOneWidget);
      expect(findLine('Step 1 of 2'), findsOneWidget);
      expect(
        find.text(connectLead(ServiceKey.seerr)),
        findsOneWidget,
        reason: 'the reason to start with Seerr is on the step itself',
      );
      expect(find.text('Start with another service'), findsOneWidget);
      expect(find.text('Test connection'), findsOneWidget);
    });

    testWidgets('a Welcome opened from inside the app can go back', (
      tester,
    ) async {
      final way = await _pumpOnboarding(tester, initialLocation: '/home');
      unawaited(way.router.push<void>(ServiceRoutes.welcome));
      await tester.pumpAndSettle();

      expect(find.byKey(onboardingHomeStandIn), findsNothing);
      expect(find.text('Back'), findsOneWidget);

      await _tap(tester, 'Back');
      expect(way.router.state.uri.path, ServiceRoutes.home);
      expect(find.byKey(onboardingHomeStandIn), findsOneWidget);
    });
  });

  group('Start with another service', () {
    testWidgets('lists every service exactly once, by what it is for', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up a service');
      await _tap(tester, 'Start with another service');

      // The two that know the others lead, under their own label, by name.
      expect(find.text('They know the others'), findsOneWidget);
      for (final service in ServiceKey.values) {
        final named =
            service == ServiceKey.seerr || service == ServiceKey.prowlarr;
        final title = named ? service.title : 'Set up ${service.title}';
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is SettingsCard &&
                w.title == title &&
                w.subtitle == (service.knowsOthers ?? service.role),
          ),
          findsOneWidget,
          reason: '$title, once, under the words that say what it is for',
        );
      }
      expect(
        find.byType(SettingsCard),
        findsNWidgets(ServiceKey.values.length),
      );
      for (final domain in ServiceDomain.values) {
        expect(find.text(domain.label), findsOneWidget, reason: domain.label);
      }
    });

    testWidgets('a row speaks one sentence and exposes its tap action', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up a service');
      await _tap(tester, 'Start with another service');

      final handle = tester.ensureSemantics();
      expect(
        find.semantics.byLabel('Set up Radarr. Movies'),
        containsSemantics(isButton: true, hasTapAction: true),
      );
      expect(
        tester
            .getSemantics(_semantics('Set up Radarr. Movies'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('choosing one rolls Connect to it, and Seerr leaves the '
        'headline', (tester) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up a service');
      expect(findLine('Set up Seerr'), findsOneWidget);

      await _tap(tester, 'Start with another service');
      await _tap(tester, 'Set up Radarr');

      expect(findLine('Set up Radarr'), findsOneWidget);
      expect(findLine('Set up Seerr'), findsNothing);
      // The step counter is for the two services that lead somewhere.
      expect(findLine('Step 1 of 2'), findsNothing);
      expect(find.text(connectLead(ServiceKey.radarr)), findsOneWidget);
    });

    testWidgets('Back returns to Connect, on the service it was opened from', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up a service');
      await _tap(tester, 'Start with another service');
      await _tap(tester, 'Back');

      expect(findLine('Set up Seerr'), findsOneWidget);
      expect(find.text('Test connection'), findsOneWidget);
    });
  });

  group('Connect', () {
    testWidgets('Back returns to the Welcome', (tester) async {
      await _pumpOnboarding(tester);
      await _openService(tester, 'Sonarr');

      await _tap(tester, 'Back');

      expect(find.text(OnePunchline.claim), findsOneWidget);
      expect(_button('Set up a service'), findsOneWidget);
      expect(find.text('Test connection'), findsNothing);
    });

    testWidgets('opened on its own, Back pops to where it came from', (
      tester,
    ) async {
      final way = await _pumpOnboarding(tester, initialLocation: '/home');
      unawaited(way.router.push<void>(ServiceRoutes.welcomeConnect));
      await tester.pumpAndSettle();
      expect(findLine('Set up Seerr'), findsOneWidget);
      // Past the claim: the door that opened it already made it.
      expect(find.text(OnePunchline.claim), findsNothing);

      await _tap(tester, 'Back');

      expect(way.router.state.uri.path, ServiceRoutes.home);
    });

    testWidgets('opened by its address, Back goes to the Welcome beneath it', (
      tester,
    ) async {
      // A deep link to Connect builds the Welcome under it, so Back pops to
      // the claim and the way in stays whole.
      final way = await _pumpOnboarding(
        tester,
        initialLocation: ServiceRoutes.welcomeConnect,
      );
      expect(findLine('Set up Seerr'), findsOneWidget);

      await _tap(tester, 'Back');

      expect(way.router.state.uri.path, ServiceRoutes.welcome);
      expect(find.text(OnePunchline.claim), findsOneWidget);
    });

    testWidgets('the step says what it wants before anything is pressed', (
      tester,
    ) async {
      // The instruction used to exist only as the outcome of pressing Test on
      // an empty form: the answer to a question the user had already had to
      // guess. It is the step's standing lead.
      await _pumpOnboarding(tester);
      await _openService(tester, 'Sonarr');

      expect(
        find.text('Enter the address and the API key, then test.'),
        findsOneWidget,
      );
    });

    testWidgets('Seerr and Prowlarr say what they already know instead', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _openService(tester, 'Prowlarr');

      expect(findLine('Set up Prowlarr'), findsOneWidget);
      expect(findLine('Step 1 of 2'), findsOneWidget);
      expect(find.text(connectLead(ServiceKey.prowlarr)), findsOneWidget);
    });

    testWidgets('one service: fill it in and test it', (tester) async {
      final way = await _pumpOnboarding(tester);
      await _openService(tester, 'Sonarr');

      await _fill(tester, url: 'sonarr.lan:8989', key: 'abcdef1234567890');

      // Test, not a way forward: the primary action only becomes one once the
      // service has actually answered.
      await _tap(tester, 'Test connection');

      // Under test the transport refuses every request, so the outcome is a
      // failure, reported as a sentence rather than a badge saying UNREACHABLE.
      // Nothing is saved for a service that did not answer, and there is no way
      // to go on without one.
      expect(_button('Test connection'), findsOneWidget);
      expect(_button('Go to Home'), findsNothing);
      expect(_skips(), findsNothing);
      expect(way.container.read(settingsProvider).sonarrUrl, isEmpty);
      expect(way.container.read(onboardingCompletedProvider), isFalse);
    });

    testWidgets(
      'an unfilled form reports what is missing, not a network fault',
      (tester) async {
        await _pumpOnboarding(tester);
        await _openService(tester, 'Sonarr');

        await _tap(tester, 'Test connection');

        // "Unreachable" blamed the network for a field nobody had typed into yet
        // and left nothing to act on.
        expect(
          find.textContaining('Enter the address and the API key'),
          findsOneWidget,
        );
        // The outcome says what the press found; the instruction stays the
        // lead above and is not said twice.
        expect(find.text('Nothing to send yet.'), findsOneWidget);
      },
    );

    testWidgets('a scheme-less host completes instead of hanging', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _openService(tester, 'Sonarr');

      await _fill(tester, url: 'sonarr.lan:8989', key: 'abcdef1234567890');
      await _tap(tester, 'Test connection');

      // A client constructor that rejects the address raises rather than
      // returning a failed status, which used to leave the button spinning for
      // the rest of the session.
      expect(
        tester.widget<FilledButton>(_button('Test connection').first).onPressed,
        isNotNull,
      );
    });

    testWidgets('the credential breadcrumb names where the key lives', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _openService(tester, 'Jellyfin');

      expect(
        find.text('Jellyfin → Dashboard → Advanced → API Keys'),
        findsOneWidget,
      );
    });

    testWidgets('the port chip puts this service default on the typed host', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _openService(tester, 'Sonarr');

      await tester.enterText(find.byType(TextField).first, 'nas.local:1234');
      await tester.pumpAndSettle();
      await tester.tap(_semantics('Use port 8989'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'https://nas.local:8989');
    });

    testWidgets('no port is offered beside a name a reverse proxy answers', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _openService(tester, 'Sonarr');
      expect(_semantics('Use port 8989'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).first,
        'https://sonarr.example.com',
      );
      await tester.pumpAndSettle();
      expect(_semantics('Use port 8989'), findsNothing);
    });

    testWidgets('another service starts with an empty address', (tester) async {
      await _pumpOnboarding(tester);
      await _openService(tester, 'Radarr');
      await _fill(tester, url: 'http://nas.local:7878', key: 'abcdef1234');

      await _tap(tester, 'Start with another service');
      await _tap(tester, 'Set up Sonarr');

      // Nothing is guessed on arrival. Carrying Radarr's host over on Sonarr's
      // default port was wrong for every reverse-proxied lab, where each
      // service has its own subdomain on 443, and cost a delete before the real
      // address could be typed.
      expect(findLine('Set up Sonarr'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, isEmpty);

      // And what was typed for Radarr waits for it, rather than going with
      // the person to the next service.
      await _tap(tester, 'Start with another service');
      await _tap(tester, 'Set up Radarr');
      final back = tester.widget<TextField>(find.byType(TextField).first);
      expect(back.controller!.text, 'http://nas.local:7878');
    });

    testWidgets('a saved service resumes in its fields', (tester) async {
      // Saving happens once a service answers, so an earlier run leaves
      // settings on disk that this screen must show: otherwise finishing a
      // second time writes empty fields over a real configuration.
      await _pumpOnboarding(
        tester,
        settings: settingsWith(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
        ),
      );
      await _openService(tester, 'Sonarr');

      final fields = find.byType(TextField);
      expect(
        tester.widget<TextField>(fields.at(0)).controller!.text,
        'https://sonarr.lan:8989',
      );
      expect(
        tester.widget<TextField>(fields.at(1)).controller!.text,
        'abcdef1234567890',
      );
    });

    testWidgets('a saved Seerr resumes on the step the door opens', (
      tester,
    ) async {
      await _pumpOnboarding(
        tester,
        settings: settingsWith(
          seerrUrl: 'https://seerr.lan:5055',
          seerrApiKey: 'abcdef1234567890',
        ),
      );
      await _tap(tester, 'Set up a service');

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'https://seerr.lan:5055');
    });
  });

  group('leaving without an answer', () {
    // The old save wrote every service that was not ready back blank, which
    // deleted the saved address and the secure credential of a service that
    // was working. The ways out that reached it are gone (Skip, unticking a
    // chip), and the ones that remain must not write at all: a service is
    // saved once it answers, and nothing before.

    testWidgets('opening a saved service and going back keeps it configured', (
      tester,
    ) async {
      final way = await _pumpOnboarding(
        tester,
        settings: settingsWith(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
        ),
      );
      await _openService(tester, 'Sonarr');

      await _tap(tester, 'Back');

      final saved = way.container.read(settingsProvider);
      expect(saved.sonarrUrl, 'https://sonarr.lan:8989');
      expect(saved.sonarrApiKey, 'abcdef1234567890');
    });

    testWidgets('choosing another service leaves a saved one configured', (
      tester,
    ) async {
      final way = await _pumpOnboarding(
        tester,
        settings: settingsWith(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
        ),
      );
      await _openService(tester, 'Sonarr');

      await _tap(tester, 'Start with another service');
      await _tap(tester, 'Set up Radarr');

      // Removing a connection is a confirmed action that lives in the settings
      // screen. Setting another one up here means "not this one now".
      final saved = way.container.read(settingsProvider);
      expect(saved.sonarrUrl, 'https://sonarr.lan:8989');
      expect(saved.sonarrApiKey, 'abcdef1234567890');
      expect(saved.radarrUrl, isEmpty);
    });

    testWidgets('a revisit keeps every saved service, credentials included', (
      tester,
    ) async {
      final way = await _pumpOnboarding(
        tester,
        settings: settingsWith(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
          qbittorrentUrl: 'https://qb.lan:8080',
          qbittorrentUsername: 'admin',
          qbittorrentPassword: 'hunter2',
        ),
      );

      await _tap(tester, 'Set up a service');
      await _tap(tester, 'Back');

      final saved = way.container.read(settingsProvider);
      expect(saved.sonarrUrl, 'https://sonarr.lan:8989');
      expect(saved.sonarrApiKey, 'abcdef1234567890');
      // The credential half too. It lives in secure storage, so losing it is
      // the one thing the user cannot undo from memory.
      expect(saved.qbittorrentUrl, 'https://qb.lan:8080');
      expect(saved.qbittorrentUsername, 'admin');
      expect(saved.qbittorrentPassword, 'hunter2');
    });

    testWidgets('a first run that types and goes back invents nothing to save', (
      tester,
    ) async {
      // The other half of the invariant: with nothing on disk there is nothing
      // to preserve, and leaving must not write half-typed values either.
      final way = await _pumpOnboarding(tester);
      await _openService(tester, 'Sonarr');
      await _fill(tester, url: 'sonarr.lan:8989', key: '');

      await _tap(tester, 'Back');

      expect(way.container.read(settingsProvider).sonarrUrl, isEmpty);
      expect(find.text(OnePunchline.claim), findsOneWidget);
    });
  });

  group('the room and the instrument', () {
    testWidgets('the ring is one instrument that survives every beat', (
      tester,
    ) async {
      await _pumpOnboarding(tester, reduceMotion: false);

      // Exactly one ring for the whole flow, mounted above the pager, so it is
      // never rebuilt from scratch when a beat changes.
      expect(find.byType(ServiceRing), findsOneWidget);
      final ringElement = tester.element(find.byType(ServiceRing));

      await tester.tap(find.text('Set up a service'));
      await _advanceFrames(tester);
      await tester.tap(find.text('Start with another service'));
      await _advanceFrames(tester);
      await tester.tap(find.text('Set up Radarr'));
      await _advanceFrames(tester);

      expect(find.byType(ServiceRing), findsOneWidget);
      expect(
        tester.element(find.byType(ServiceRing)),
        same(ringElement),
        reason: 'the same element, so its animation state is continuous',
      );
      expect(findLine('Set up Radarr'), findsOneWidget);

      // Bounded pumps only: the sweep repeats forever by design, so settling is
      // not something this screen ever does with motion on.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a beat arrives rather than sliding in', (tester) async {
      // The whole flow must be completable without one tween. The page slide
      // was the biggest hole in it: every way between two beats went through
      // `animateToPage`.
      await _pumpOnboarding(tester);

      await tester.tap(find.text('Set up a service'));
      // One frame, deliberately not a settle: with the animator gone the pager
      // is already on Connect by the time the frame is built.
      await tester.pump();

      final pager = tester.widget<PageView>(find.byType(PageView));
      expect(pager.controller!.page, 2);
      expect(findLine('Set up Seerr'), findsOneWidget);

      await tester.tap(find.text('Start with another service'));
      await tester.pump();
      expect(pager.controller!.page, 1);
      expect(find.text('They know the others'), findsOneWidget);
    });

    testWidgets('the room is lit by the lamp on every beat, the walk too', (
      tester,
    ) async {
      // The brand book: a room with no artwork is lit by the neutral lamp, and a
      // service's room is no exception: the service being set up is named by its
      // mark and its form, never by a colour. The room used to take the
      // service's accent during the walk and the brand primary either side of it
      // (the primary is the ink now, which would have lit the room white).
      await _pumpOnboarding(tester);
      const brand = AppColors.lamp;

      // Read off the gradient the room actually paints, not off the argument it
      // was handed. `AmbientBackground` resolves its own fallback and tweens the
      // accent now, so the constructor argument is null on the beats that want
      // the brand glow, and asserting on it would be asserting on the plumbing
      // rather than on the rule.
      Color roomAccent() {
        final decorated = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(AmbientBackground),
                matching: find.byType(DecoratedBox),
              ),
            )
            .firstWhere(
              (box) => (box.decoration as BoxDecoration).gradient != null,
            );
        final gradient =
            (decorated.decoration as BoxDecoration).gradient as RadialGradient;
        // The accent is the first stop, painted at the theme's wash alpha.
        return gradient.colors.first.withValues(alpha: 1.0);
      }

      // The Welcome is the lamp.
      expect(roomAccent(), brand);

      await _openService(tester, 'Sonarr');
      // And so is Connect: Sonarr's room is the same light.
      expect(roomAccent(), brand);
      expect(roomAccent(), isNot(ServiceKey.sonarr.brandAccent));

      await _tap(tester, 'Back');
      expect(roomAccent(), brand);
    });

    testWidgets('the ring speaks its state rather than only drawing it', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      expect(
        _semantics('${ServiceKey.values.length} services, none set up yet'),
        findsWidgets,
      );

      await _tap(tester, 'Set up a service');
      expect(
        _semantics('1 of ${ServiceKey.values.length} chosen'),
        findsWidgets,
      );
    });
  });

  group('sizes', () {
    testWidgets('compact desktop keeps long-form actions reachable', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final settings = const SettingsModel().copyWithService(
          ServiceKey.readarr,
          url: 'http://127.0.0.1:8787',
          apiKey: 'test-key',
        );
        await _pumpOnboarding(
          tester,
          settings: settings,
          viewport: const Size(720, 450),
        );
        await _tap(tester, 'Set up a service');
        await _tap(tester, 'Start with another service');
        // A short window scrolls the list, and the pager must not move.
        await tester.scrollUntilVisible(
          find.text('Set up Readarr'),
          100,
          scrollable: find
              .descendant(
                of: find.byType(OnboardingStart),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Set up Readarr'));
        await tester.pumpAndSettle();

        // Notes on the long-form services used to push the footer below the
        // compact desktop window. The form may scroll, but the decision cannot
        // require a user to discover an invisible primary action first.
        expect(
          find.textContaining('Readarr development has stopped'),
          findsOneWidget,
        );
        final testButton = tester.getRect(_button('Test connection').first);
        expect(testButton.bottom, lessThanOrEqualTo(450));
        expect(
          tester.getRect(find.widgetWithText(TextButton, 'Back')).bottom,
          lessThanOrEqualTo(450),
        );
      } finally {
        // Cleared before the test binding checks its foundation invariants.
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('no beat overflows a short phone at an accessibility size', (
      tester,
    ) async {
      await _pumpOnboarding(
        tester,
        textScale: 2.0,
        // The viewport where a display headline, a paragraph and two buttons
        // stopped fitting first.
        viewport: const Size(375, 667),
      );

      // Each beat is a scrollable whose content is centred while it fits, so
      // nothing overflows and the actions stay pinned and reachable.
      expect(tester.takeException(), isNull);
      expect(_button('Set up a service'), findsOneWidget);

      await _tap(tester, 'Set up a service');
      expect(tester.takeException(), isNull);
      expect(_button('Test connection'), findsOneWidget);

      await _reachAndTapStartElsewhere(tester);
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);

      await _tap(tester, 'Back');
      expect(tester.takeException(), isNull);
      expect(_button('Test connection'), findsOneWidget);

      await _tap(tester, 'Back');
      expect(tester.takeException(), isNull);
      expect(_button('Set up a service'), findsOneWidget);
    });

    for (final (size, name) in [
      (const Size(390, 844), 'a tall phone'),
      (const Size(375, 667), 'a short one'),
    ]) {
      testWidgets('another service stays reachable at an accessibility size, '
          'on $name', (tester) async {
        // At this reading size the instrument takes the short screen's
        // register, which folds the headline, the lead and the link under
        // them away to leave the form its room. The link goes to the foot of
        // the form then, so Radarr is not out of reach for a person who needs
        // the text this large: the door only ever opens Seerr.
        await _pumpOnboarding(tester, textScale: 2.0, viewport: size);
        await _tap(tester, 'Set up a service');
        expect(find.text(connectLead(ServiceKey.seerr)), findsNothing);
        expect(find.text('Start with another service'), findsOneWidget);

        await _reachAndTapStartElsewhere(tester);

        expect(
          find.byType(SettingsCard),
          findsNWidgets(ServiceKey.values.length),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Connect keeps its action and Back at an accessibility size', (
      tester,
    ) async {
      await _pumpOnboarding(tester, textScale: 2.0);
      await _openService(tester, 'Sonarr');

      // The only two actions Connect has, and both survive the reading size.
      expect(_button('Test connection'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a full configuration fits a phone on every beat', (
      tester,
    ) async {
      await _pumpOnboarding(
        tester,
        settings: _fullConfiguration(),
        viewport: const Size(390, 844),
      );
      // Resumed: Seerr opens on its saved address and key, and the list of
      // every service is the longest page the flow has.
      expect(tester.takeException(), isNull);
      await _tap(tester, 'Set up a service');
      expect(tester.takeException(), isNull);
      await _tap(tester, 'Start with another service');
      expect(tester.takeException(), isNull);
      expect(
        find.byType(SettingsCard),
        findsNWidgets(ServiceKey.values.length),
      );
    });
  });

  /// A 6.1" phone with the keyboard up, which is the real posture for the only
  /// beat that asks the user to type.
  ///
  /// The ring, the subject line and the pinned footer all have fixed heights
  /// and sat above an `Expanded`, so the form absorbed the entire shortfall:
  /// on this viewport it was left roughly 60pt, which clipped the address field
  /// mid-glyph and hid the validation line that explains why the step will not
  /// advance. The ring now gives its slot back instead.
  group('with the keyboard up', () {
    const phone = Size(393, 852);
    const keyboard = 336.0;

    Future<void> reachTheForm(WidgetTester tester) =>
        _openService(tester, 'Sonarr');

    /// Raises the keyboard the way the platform does, after the field has
    /// focus, by shrinking the view, rather than pumping a screen that was
    /// already short. Pumping it up front would test a state the user never
    /// reaches, since the beats before Connect have nothing to type into.
    Future<void> raiseKeyboard(WidgetTester tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
    }

    testWidgets('the ring holds its place while the keyboard is down', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);

      expect(find.byType(ServiceRing), findsOneWidget);
    });

    testWidgets('the ring changes register rather than leaving', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      final before = tester.widget<ServiceRing>(find.byType(ServiceRing));
      final full = before.diameter;
      expect(before.markFraction, ServiceRing.defaultMarkFraction);

      await raiseKeyboard(tester);

      // The defect this replaces: the full register asks for whatever the beat
      // leaves over, and with a software keyboard up that is nothing on every
      // phone, so the instrument was not merely smaller, it was gone for the
      // whole time the user was typing.
      expect(find.byType(ServiceRing), findsOneWidget);
      final after = tester.widget<ServiceRing>(find.byType(ServiceRing));
      expect(after.diameter, lessThan(full));
      expect(
        after.diameter,
        greaterThanOrEqualTo(96),
        reason: 'under its own floor the ring is a smudge, not an instrument',
      );
      // The mark gives up proportionally more than the ring does, because the
      // nodes keep an absolute radius and would otherwise crowd it.
      expect(after.markFraction, lessThan(ServiceRing.defaultMarkFraction));
    });

    testWidgets('the compact register keeps the ring inside the screen', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      await raiseKeyboard(tester);

      final ring = tester.getRect(find.byType(ServiceRing));
      expect(ring.top, greaterThanOrEqualTo(0));
      expect(
        ring.bottom,
        lessThanOrEqualTo(phone.height - keyboard),
        reason: 'a ring drawn under the keyboard is no better than no ring',
      );
    });

    testWidgets('the eyebrow moves beside the ring and the lead goes', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      expect(findLine('Set up Sonarr'), findsOneWidget);
      expect(find.text(connectLead(ServiceKey.sonarr)), findsOneWidget);

      await raiseKeyboard(tester);

      // The orientation survives the register change: which service, said
      // exactly once, because a duplicated eyebrow is two steps to a screen
      // reader. In this register the glyph tile and the headline are both
      // gone, and the eyebrow is what still names the subject.
      expect(findLine('Set up Sonarr'), findsOneWidget);
      final label = tester.getRect(findLine('Set up Sonarr'));
      final ring = tester.getRect(find.byType(ServiceRing));
      expect(
        label.left,
        greaterThanOrEqualTo(ring.right),
        reason:
            'the compact register puts the label beside the ring, not under',
      );
      // The lead is what pays for the row: while the keyboard is up the user is
      // already answering it, into a field labelled Address.
      expect(find.text(connectLead(ServiceKey.sonarr)), findsNothing);
    });

    testWidgets('the way to another service moves to the foot of the form', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      expect(find.text('Start with another service'), findsOneWidget);
      final under = tester.getRect(find.text('Start with another service'));
      expect(
        under.bottom,
        lessThan(tester.getRect(find.text('Address')).top),
        reason: 'under the headline, above the form',
      );

      await raiseKeyboard(tester);

      // Folded away with the subject it sat under, and still there: once,
      // below the fields, for a person who hides the keyboard and wants
      // another service.
      expect(find.text('Start with another service'), findsOneWidget);
      final foot = tester.getRect(find.text('Start with another service'));
      expect(
        foot.top,
        greaterThan(tester.getRect(find.text('API key')).bottom),
      );
    });

    testWidgets('the eyebrow of a service with a second step says so', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await _tap(tester, 'Set up a service');
      expect(findLine('Step 1 of 2'), findsOneWidget);

      await raiseKeyboard(tester);

      // The step counter folds into the eyebrow with the service, so the
      // compact register still says how far in the person is.
      expect(findLine('Set up Seerr · step 1 of 2'), findsOneWidget);
      expect(findLine('Step 1 of 2'), findsNothing);
    });

    testWidgets('the return key walks the form and then tests', (tester) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);

      final address = find.byType(TextField).first;
      final apiKey = find.byType(TextField).last;
      await tester.tap(address);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(address).focusNode?.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();

      // Not the framework's own handling of `next`, which would hand focus to
      // the port chip sitting inside the address field.
      expect(tester.widget<TextField>(apiKey).focusNode?.hasFocus, isTrue);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The last field ends the form by running the test, and the test takes
      // the keyboard with it, so the outcome and the pinned actions are what
      // comes back rather than a verdict answered behind the keys.
      expect(tester.widget<TextField>(apiKey).focusNode?.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('Nothing to send yet.'), findsOneWidget);
    });

    testWidgets('the address field stays clear of the keyboard', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      await raiseKeyboard(tester);

      final field = find.byType(TextField).first;
      final rect = tester.getRect(field);

      expect(rect.height, greaterThan(0));
      // The whole control, not just its top edge: a field cut off at the
      // baseline is what the screenshots showed.
      expect(
        rect.bottom,
        lessThanOrEqualTo(phone.height - keyboard),
        reason:
            'the address field runs under the keyboard: bottom ${rect.bottom} '
            'against a ${phone.height - keyboard} fold',
      );
      expect(rect.top, greaterThanOrEqualTo(0));
    });

    testWidgets('the primary action stays reachable', (tester) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      await raiseKeyboard(tester);

      final button = tester.getRect(_button('Test connection').first);
      expect(button.bottom, lessThanOrEqualTo(phone.height - keyboard));
    });

    testWidgets('a shallow inset keeps the ring rather than dumping it', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);

      // A hardware or floating keyboard reports only its accessory strip. The
      // first version of this hid the ring on `viewInsets > 0` alone, which
      // emptied half the screen for nothing.
      tester.view.viewInsets = const FakeViewPadding(bottom: 90);
      await tester.pumpAndSettle();

      expect(find.byType(ServiceRing), findsOneWidget);
      final field = tester.getRect(find.byType(TextField).first);
      expect(field.bottom, lessThanOrEqualTo(phone.height - 90));
    });

    testWidgets('leaving Connect takes the keyboard with it', (tester) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);

      await _tap(tester, 'Back');

      // A focused `EditableText` registers a keep-alive, so the step the user
      // left stayed mounted and focused: the next beat arrived with the
      // keyboard still covering half of it, and keystrokes went into a field
      // that was no longer on screen.
      expect(find.text(OnePunchline.claim), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(
        find
            .byType(TextField)
            .evaluate()
            .where((e) => (e.widget as TextField).focusNode?.hasFocus ?? false),
        isEmpty,
      );
    });

    testWidgets('choosing another service takes the keyboard with it', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);

      await tester.tap(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);

      await _tap(tester, 'Start with another service');

      expect(find.text('They know the others'), findsOneWidget);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('a way to put the keyboard away appears with it', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      expect(find.text('Hide keyboard'), findsNothing);

      await raiseKeyboard(tester);

      // iOS gives the URL keyboard no dismissing return key, so without this
      // there is no key to press on the one beat that asks the user to type.
      expect(find.text('Hide keyboard'), findsOneWidget);
      final bar = tester.getRect(find.text('Hide keyboard'));
      expect(bar.bottom, lessThanOrEqualTo(phone.height - keyboard));
    });

    testWidgets('a keyboard put away comes back with a tap on the field', (
      tester,
    ) async {
      await _pumpOnboarding(tester, viewport: phone);
      await reachTheForm(tester);
      final field = find.byType(TextField).first;
      await tester.tap(field);
      await tester.pumpAndSettle();
      await raiseKeyboard(tester);

      await tester.tap(find.text('Hide keyboard'));
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      final node = tester.widget<TextField>(field).focusNode!;
      expect(node.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(node.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });
  });
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

/// Anything on screen that offers a way past a service: the word, in a label
/// or a button, in any case.
Finder _skips() => find.byWidgetPredicate(
  (widget) =>
      (widget is Text && (widget.data ?? '').toLowerCase().contains('skip')) ||
      (widget is Semantics &&
          (widget.properties.label ?? '').toLowerCase().contains('skip')),
);

/// Matches a [Semantics] widget by its declared label.
///
/// Read off the widget rather than the semantics tree so the harness needs no
/// [SemanticsHandle]: `ensureSemantics`' handle is verified as disposed before
/// `addTearDown` callbacks run, so the idiomatic pairing fails every test.
Finder _semantics(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// Taps by visible label.
///
/// Deliberately no `ensureVisible`: `Scrollable.ensureVisible` walks *every*
/// enclosing scrollable, and these beats live inside a horizontal `PageView`, so
/// revealing a pinned footer button scrolls the pager off the page and unbuilds
/// the very widget being reached for. The tall viewport in [_pumpOnboarding] is
/// what makes scrolling unnecessary instead.
Future<void> _tap(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  final target = find.text(label);
  await tester.tap(target.first);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Connect for [title]: the door, then the list, then the row.
///
/// Seerr and Prowlarr are rows by name ("They know the others"); every other
/// service is `Set up <name>`.
Future<void> _openService(WidgetTester tester, String title) async {
  await _tap(tester, 'Set up a service');
  await _tap(tester, 'Start with another service');
  final named = title == 'Seerr' || title == 'Prowlarr';
  final row = find.text(named ? title : 'Set up $title');
  // The list is long, and a phone's window shows a part of it: scrolled to by
  // the list's own scrollable, so the pager is never asked to move.
  await tester.scrollUntilVisible(
    row,
    100,
    scrollable: find
        .descendant(
          of: find.byType(OnboardingStart),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// Taps "Start with another service" wherever Connect keeps it: under the
/// headline, or at the foot of the form once the subject is folded away.
///
/// Scrolled to by the form's own scrollable, so the pager is never asked to
/// move.
Future<void> _reachAndTapStartElsewhere(WidgetTester tester) async {
  final link = find.text('Start with another service');
  await tester.scrollUntilVisible(
    link,
    100,
    scrollable: find
        .descendant(
          of: find.byType(OnboardingWalk),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(link);
  await tester.pumpAndSettle();
}

/// Pumps a handful of real frames.
///
/// With the sweep running there is no settled state, so motion-on cases advance
/// the clock in steps instead of waiting for one, and a single long pump is not
/// enough, because a pager builds the arriving page over more than one frame.
Future<void> _advanceFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _fill(
  WidgetTester tester, {
  required String url,
  required String key,
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), url);
  await tester.enterText(fields.at(1), key);
  await tester.pumpAndSettle();
}

/// Every service configured, built from the registry rather than written out.
///
/// The hand-written literal this replaces silently stopped covering the whole
/// list the moment a service was added, and the case it feeds is precisely "does
/// the longest possible configuration still fit a phone", so it has to grow
/// with the registry or it stops testing what it claims to.
SettingsModel _fullConfiguration() {
  var settings = const SettingsModel();
  for (final service in ServiceKey.values) {
    final url = 'https://${service.name}.lan:${service.defaultPort}';
    settings = service.usesApiKey
        ? settings.copyWithService(service, url: url, apiKey: 'k')
        : settings.copyWithCredentials(
            service,
            url: url,
            username: 'u',
            password: 'p',
          );
  }
  return settings;
}

/// What a case reads back: the container, for what the way in saved, and the
/// router, for where it left for.
typedef _Way = ({ProviderContainer container, GoRouter router});

Future<_Way> _pumpOnboarding(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  double textScale = 1.0,
  Size? viewport,
  bool reduceMotion = true,
  String initialLocation = ServiceRoutes.welcome,
}) async {
  // Tall enough that no beat needs scrolling, so a tap never has to reach past
  // the fold. See [_tap] for why scrolling is the thing to avoid here. Width is
  // irrelevant past `onboardingMaxWidth`.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport ?? const Size(800, 2400);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secureStore = FakeSecureSettingsStore();

  // An explicit container, so a case can read back what the way in actually
  // saved (the difference between "left" and "deleted" is invisible on screen).
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(secureStore),
      initialSettingsProvider.overrideWith((ref) => settings),
      initialOnboardingCompletedProvider.overrideWith((ref) => false),
    ],
  );
  addTearDown(container.dispose);

  final router = onboardingRouter(initialLocation: initialLocation);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Injected through `builder`, not by wrapping MaterialApp: MaterialApp
      // installs its own MediaQuery from the view and would discard an outer
      // one, so the reading size would silently stay at 1.0.
      //
      // Reduce Motion is the default here, and not only for speed: the ring's
      // ambient sweep repeats forever, so with motion on `pumpAndSettle` waits
      // for a frame that never stops coming. Motion has its own case above,
      // pumped in bounded steps.
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
      ),
    ),
  );
  if (reduceMotion) {
    await tester.pumpAndSettle();
  } else {
    // With the sweep running there is no settled state to wait for.
    await tester.pump(const Duration(milliseconds: 600));
  }
  return (container: container, router: router);
}
