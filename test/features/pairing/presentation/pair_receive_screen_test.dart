/// Copying from another device, as the new device sees it: where the code
/// comes from, what a link pasted or scanned does, what arrived, and Add.
/// Driven by fixed states where the words are the point, and by the protocol
/// itself, on loopback, once.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/pairing/data/pair_fetch.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/pairing/presentation/pair_receive_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/onboarding_router.dart';
import '../../../test_helpers/pair_fixtures.dart';
import '../../../test_helpers/settings_scope.dart';

/// The screen at `/welcome/pair`, with a stand-in Home to leave for.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  PairNetwork network = const PairNetwork(),
  List<Override> overrides = const [],
  PairArrival? arrival,
  bool onboardingCompleted = true,
  bool underTheWelcome = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...await settingsScopeOverrides(customize: (_) => settings),
      pairNetworkProvider.overrideWithValue(network),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  container.read(onboardingCompletedProvider.notifier).state =
      onboardingCompleted;
  if (arrival != null) {
    container.read(pendingPairProvider.notifier).hold(arrival);
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  // As the app mounts it, the Welcome is the page under this one; without it
  // the screen is all there is, as a link opened the app on it.
  final router = GoRouter(
    initialLocation: ServiceRoutes.welcomePair,
    routes: [
      if (underTheWelcome)
        GoRoute(
          path: ServiceRoutes.welcome,
          builder: (_, _) => const Text('Welcome'),
          routes: [
            GoRoute(path: 'pair', builder: (_, _) => const PairReceiveScreen()),
            GoRoute(
              path: 'sign-in',
              builder: (_, _) => const Scaffold(body: Text('Sign in')),
            ),
          ],
        )
      else
        GoRoute(
          path: ServiceRoutes.welcomePair,
          builder: (_, _) => const PairReceiveScreen(),
        ),
      // Where an invite shown in person goes on to.
      GoRoute(
        path: ServiceRoutes.settingsAccount,
        builder: (_, state) =>
            Scaffold(body: Text('Account ${state.uri.queryParameters['i']}')),
      ),
      GoRoute(
        path: Uri.parse(ServiceRoutes.settingsFor(ServiceKey.seerr)).path,
        builder: (_, state) => Scaffold(
          body: Text('Seerr form ${state.uri.queryParameters['i']}'),
        ),
      ),
      GoRoute(
        path: ServiceRoutes.home,
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('Home', key: onboardingHomeStandIn)),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  // Not settled: the busy line's spinner turns for as long as it is there.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

/// The glyph of the notice and the colour it is drawn in.
Color _noticeInk(WidgetTester tester, IconData glyph) {
  final icon = tester.widget<Icon>(find.byIcon(glyph));
  return icon.color!;
}

Finder _field() => find.byType(TextField);

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(_field()).controller!.text;

/// The filled button that says [label]. By subtype: a button with a glyph
/// beside its label (the busy one) is a subclass of `FilledButton`.
Finder _filledButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<FilledButton>(),
);

FilledButton _filled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(_filledButton(label));

void main() {
  group('waiting for a link', () {
    testWidgets('says how to get one, and asks for it in a field', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Copy from another device'), findsOneWidget);
      expect(
        find.text(
          'On the device that has Cupola set up, open Settings › Set up '
          "another device, then point this phone's camera at its code.",
        ),
        findsOneWidget,
      );
      expect(find.text('Link from the other device'), findsOneWidget);
      expect(_field(), findsOneWidget);
    });

    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      testWidgets('on ${platform.name} it is copied and pasted, not scanned', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await _pump(tester);
          expect(
            find.text(
              'On the device that has Cupola set up, open Settings › Set up '
              'another device, copy its link and paste it here.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('camera'), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('a link on its way in is fetched at once, and held nowhere', (
      tester,
    ) async {
      final fetched = <PairLink>[];
      final reaching = Completer<PairPackage>();
      final link = pairFixtureLink();
      final container = await _pump(
        tester,
        network: PairNetwork(
          fetch: (link) {
            fetched.add(link);
            return reaching.future;
          },
        ),
        arrival: PairArrival(link),
      );

      expect(fetched, [link]);
      expect(find.text('Fetching from the other device'), findsOneWidget);
      expect(container.read(pendingPairProvider), isNull);
      reaching.completeError(
        const PairFetchException(PairFetchFailure.unreachable),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a link that did not arrive whole says so', (tester) async {
      await _pump(tester, arrival: const PairArrival(null));

      expect(find.text("This link isn't whole"), findsOneWidget);
      expect(
        find.text('Copy it again, or make a new code on the other device.'),
        findsOneWidget,
      );
    });
  });

  group('a link pasted in the field', () {
    testWidgets('a message with the link in it starts the fetch, and the '
        'field is empty', (tester) async {
      final fetched = <PairLink>[];
      final reaching = Completer<PairPackage>();
      final link = pairFixtureLink();
      await _pump(
        tester,
        network: PairNetwork(
          fetch: (link) {
            fetched.add(link);
            return reaching.future;
          },
        ),
      );

      await tester.enterText(
        _field(),
        'Copy me from the other phone: ${link.toLink()} (two minutes)',
      );
      await tester.pump();

      expect(fetched, [link]);
      expect(find.text('Fetching from the other device'), findsOneWidget);

      // The key is in no text the screen draws and in no field.
      expect(find.textContaining(pairFixtureKey), findsNothing);
      reaching.completeError(
        const PairFetchException(PairFetchFailure.unreachable),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start again'));
      await tester.pumpAndSettle();
      expect(_fieldText(tester), isEmpty);
    });

    testWidgets('a broken link says it is not whole, and is not kept', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(
        _field(),
        'cupola://pair?v=1&h=192.168.1.20:47213&k=cut-short',
      );
      await tester.pumpAndSettle();

      expect(find.text("This link isn't whole"), findsOneWidget);
      // Offered again from the start, the field is empty.
      await tester.tap(find.text('Start again'));
      await tester.pumpAndSettle();
      expect(_fieldText(tester), isEmpty);
    });

    testWidgets('an address, or anything else, is left alone', (tester) async {
      var fetches = 0;
      await _pump(
        tester,
        network: PairNetwork(
          fetch: (_) async {
            fetches++;
            throw const PairFetchException(PairFetchFailure.unreachable);
          },
        ),
      );

      await tester.enterText(_field(), 'http://192.168.1.20:7878');
      await tester.pumpAndSettle();

      expect(fetches, 0);
      expect(find.text('Link from the other device'), findsOneWidget);
      expect(_fieldText(tester), 'http://192.168.1.20:7878');
    });
  });

  group('when nothing arrived', () {
    Future<FixedReceive> failed(
      WidgetTester tester,
      PairReceiveFailure failure,
    ) async {
      final fixed = fixedReceive(PairReceiveFailed(failure));
      await _pump(tester, overrides: [fixed.override]);
      return fixed;
    }

    testWidgets('unreachable is red, and offers Retry then Start again, both '
        'in ink', (tester) async {
      final fixed = await failed(tester, PairReceiveFailure.unreachable);

      expect(
        find.text("Cupola could not reach the other device"),
        findsOneWidget,
      );
      expect(find.text('Both need to be on the same Wi-Fi.'), findsOneWidget);
      expect(
        _noticeInk(tester, Icons.cloud_off_rounded),
        statusToneColor(
          _scheme(tester),
          StatusTone.error,
          surface: _scheme(tester).surface,
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.widgetWithText(TextButton, Lexicon.retry), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Start again'), findsOneWidget);

      await tester.tap(find.text(Lexicon.retry));
      await tester.tap(find.text('Start again'));
      expect(fixed.notifier.retries, 1);
      expect(fixed.notifier.resets, 1);
    });

    testWidgets('expired is blue, and offers Start again in ink, no Retry', (
      tester,
    ) async {
      final fixed = await failed(tester, PairReceiveFailure.expired);

      expect(find.text('This code has expired'), findsOneWidget);
      expect(find.text('Make a new code on the other device.'), findsOneWidget);
      expect(
        _noticeInk(tester, Icons.info_outline_rounded),
        statusToneColor(
          _scheme(tester),
          StatusTone.info,
          surface: _scheme(tester).surface,
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text(Lexicon.retry), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Start again'));
      expect(fixed.notifier.resets, 1);
    });

    final amber = {
      PairReceiveFailure.unreadable: (
        "Cupola could not read what the other device sent",
        'Make a new code on the other device.',
      ),
      PairReceiveFailure.newer: (
        'This came from a newer Cupola',
        'Update Cupola on this device, then make a new code.',
      ),
      PairReceiveFailure.notWhole: (
        "This link isn't whole",
        'Copy it again, or make a new code on the other device.',
      ),
    };
    for (final MapEntry(key: failure, value: words) in amber.entries) {
      testWidgets('${failure.name} is amber, and its one fill is Start again, '
          'with no Retry', (tester) async {
        final fixed = await failed(tester, failure);

        expect(find.text(words.$1), findsOneWidget);
        expect(find.text(words.$2), findsOneWidget);
        expect(
          _noticeInk(tester, Icons.error_outline_rounded),
          statusToneColor(
            _scheme(tester),
            StatusTone.warning,
            surface: _scheme(tester).surface,
          ),
        );
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.text(Lexicon.retry), findsNothing);
        await tester.tap(find.widgetWithText(FilledButton, 'Start again'));
        expect(fixed.notifier.resets, 1);
      });
    }

    testWidgets('a notice is heard as one sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await failed(tester, PairReceiveFailure.expired);
      expect(
        find.bySemanticsLabel(
          'This code has expired. Make a new code on the other device.',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('what arrived', () {
    testWidgets('names the device, counts what is new, and lists each '
        'connection by its title and where it is', (tester) async {
      final plan = pairFixturePlan(
        settings: const SettingsModel(
          instances: [
            ServiceInstance(
              id: 'sonarr',
              service: ServiceKey.sonarr,
              url: 'http://192.168.1.10:8989',
              credential: 'mine',
            ),
          ],
        ),
      );
      await _pump(
        tester,
        overrides: [fixedReceive(PairReceivePreview(plan)).override],
      );

      expect(find.text('From your iPhone'), findsOneWidget);
      // Three new (the Sonarr is here already), one certificate.
      expect(
        find.text(
          '3 services\u00A0· 1 trusted certificate\u00A0· 1 already here',
        ),
        findsOneWidget,
      );
      expect(find.text('Radarr'), findsOneWidget);
      expect(find.text('radarr.home.arpa'), findsOneWidget);
      expect(find.text('Seerr'), findsOneWidget);
      expect(find.text('192.168.1.10:5055'), findsOneWidget);
      expect(find.text('qBittorrent'), findsOneWidget);
      expect(find.text('Sonarr'), findsNothing);
      expect(find.text('Add 3 services'), findsOneWidget);
      expect(find.text('Start again'), findsOneWidget);
    });

    testWidgets('a row speaks one sentence', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        overrides: [
          fixedReceive(PairReceivePreview(pairFixturePlan())).override,
        ],
      );
      expect(
        find.bySemanticsLabel('Radarr at radarr.home.arpa'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Seerr at 192.168.1.10:5055'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('says what comes without its secret, and what signs in '
        'again, only when it applies', (tester) async {
      await _pump(
        tester,
        overrides: [
          fixedReceive(PairReceivePreview(pairFixturePlan())).override,
        ],
      );
      expect(
        find.text(
          'Sign in to Seerr again here. A sign-in stays on the device it '
          'was made on.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "qBittorrent arrives without its password. Paste it here once it's "
          'added.',
        ),
        findsOneWidget,
      );
      // Nothing of a service this version does not know.
      expect(find.textContaining("doesn't know"), findsNothing);
    });

    testWidgets('a plain package has no notes', (tester) async {
      final plain = PairPackage(
        from: PairDevice.mac,
        connections: const [
          ServiceInstance(
            id: 'p',
            service: ServiceKey.radarr,
            url: 'http://192.168.1.10:7878',
            credential: 'k',
          ),
        ],
      );
      await _pump(
        tester,
        overrides: [
          fixedReceive(
            PairReceivePreview(pairFixturePlan(package: plain)),
          ).override,
        ],
      );
      expect(find.text('From your Mac'), findsOneWidget);
      expect(find.text('1 service'), findsOneWidget);
      expect(find.text('Add 1 service'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    });

    for (final (n, words) in [
      (1, "1 service this version of Cupola doesn't know stays behind."),
      (3, "3 services this version of Cupola doesn't know stay behind."),
    ]) {
      testWidgets('says what a newer Cupola sent that this one does not '
          'know ($n)', (tester) async {
        final package = PairPackage(
          from: PairDevice.ipad,
          connections: const [
            ServiceInstance(
              id: 'p',
              service: ServiceKey.radarr,
              url: 'http://192.168.1.10:7878',
              credential: 'k',
            ),
          ],
          unknown: n,
        );
        await _pump(
          tester,
          overrides: [
            fixedReceive(
              PairReceivePreview(pairFixturePlan(package: package)),
            ).override,
          ],
        );
        expect(find.text(words), findsOneWidget);
      });
    }

    testWidgets('a connection with a label is named by it', (tester) async {
      final labelled = PairPackage(
        from: PairDevice.iphone,
        connections: const [
          ServiceInstance(
            id: 'a',
            service: ServiceKey.radarr,
            url: 'http://192.168.1.10:7878',
            credential: 'k',
          ),
          ServiceInstance(
            id: 'b',
            service: ServiceKey.radarr,
            label: '4K',
            url: 'http://192.168.1.10:7879',
            credential: 'k',
          ),
        ],
      );
      await _pump(
        tester,
        overrides: [
          fixedReceive(
            PairReceivePreview(pairFixturePlan(package: labelled)),
          ).override,
        ],
      );
      expect(find.text('Radarr'), findsOneWidget);
      expect(find.text('Radarr\u00A0· 4K'), findsOneWidget);
    });

    testWidgets('a pin for a server already here is not added', (tester) async {
      final onlyPins = PairPackage(
        from: PairDevice.iphone,
        connections: const [
          ServiceInstance(
            id: 'a',
            service: ServiceKey.radarr,
            url: 'https://radarr.home.arpa',
            credential: 'k',
          ),
        ],
        certificates: const {'https://radarr.home.arpa:443': pairFixturePin},
      );
      final plan = PairPlan.of(
        onlyPins,
        const SettingsModel(
          instances: [
            ServiceInstance(
              id: 'mine',
              service: ServiceKey.radarr,
              url: 'https://radarr.home.arpa',
              credential: 'mine',
            ),
          ],
        ),
      );
      await _pump(
        tester,
        overrides: [fixedReceive(PairReceivePreview(plan)).override],
      );
      expect(find.text('1 already here'), findsOneWidget);
      expect(find.text('Add 1 trusted certificate'), findsNothing);
      expect(
        find.text('Everything from your iPhone is already here.'),
        findsOneWidget,
      );
    });

    testWidgets('when nothing is new it says so, and offers Done', (
      tester,
    ) async {
      final plan = PairPlan.of(pairFixturePackage(), pairFixtureSender());
      expect(plan.addsAnything, isFalse);
      await _pump(
        tester,
        overrides: [fixedReceive(PairReceivePreview(plan)).override],
      );
      expect(
        find.text('Everything from your iPhone is already here.'),
        findsOneWidget,
      );
      expect(find.textContaining('Add '), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.byKey(onboardingHomeStandIn), findsOneWidget);
    });

    testWidgets('Add asks the notifier once, and Start again begins afresh', (
      tester,
    ) async {
      final fixed = fixedReceive(PairReceivePreview(pairFixturePlan()));
      await _pump(tester, overrides: [fixed.override]);

      await tester.tap(_filledButton('Add 4 services'));
      await tester.tap(find.widgetWithText(TextButton, 'Start again'));
      expect(fixed.notifier.adds, 1);
      expect(fixed.notifier.resets, 1);
    });

    testWidgets('while it writes, the primary is busy and cannot be tapped '
        'twice', (tester) async {
      final fixed = fixedReceive(PairReceiveAdding(pairFixturePlan()));
      await _pump(tester, overrides: [fixed.override]);

      expect(_filled(tester, 'Add 4 services').onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Add 4 services'), warnIfMissed: false);
      expect(fixed.notifier.adds, 0);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Start again'))
            .onPressed,
        isNull,
      );
    });
  });

  group('adding', () {
    testWidgets('writes what arrived over what is here, and lands on the '
        'Home', (tester) async {
      final container = await _pump(
        tester,
        network: PairNetwork(fetch: (_) async => pairFixturePackage()),
        arrival: PairArrival(pairFixtureLink()),
      );
      expect(find.text('Add 4 services'), findsOneWidget);

      await tester.tap(_filledButton('Add 4 services'));
      await tester.pumpAndSettle();

      expect(find.byKey(onboardingHomeStandIn), findsOneWidget);
      final settings = container.read(currentSettingsProvider);
      expect(settings.instances, hasLength(4));
      expect(
        settings.instancesOf(ServiceKey.radarr).single.credential,
        'radarr-fixture-key',
      );
      expect(
        settings.trustedCertificates['https://radarr.home.arpa:443'],
        pairFixturePin,
      );
      expect(container.read(onboardingCompletedProvider), isTrue);
    });
  });

  group('Back', () {
    testWidgets('from what arrived, goes back to waiting for a link', (
      tester,
    ) async {
      final fixed = fixedReceive(PairReceivePreview(pairFixturePlan()));
      await _pump(tester, overrides: [fixed.override]);

      await tester.tap(find.byType(BackButton));
      expect(fixed.notifier.resets, 1);
    });

    testWidgets('from waiting, goes back to the page it came from', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
    });

    testWidgets('with nothing under it, leaves for the Welcome on a first '
        'run', (tester) async {
      await _pump(tester, onboardingCompleted: false, underTheWelcome: false);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(PairReceiveScreen), findsNothing);
    });

    testWidgets('with nothing under it, leaves for the Home once the way in '
        'is over', (tester) async {
      await _pump(tester, underTheWelcome: false);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byKey(onboardingHomeStandIn), findsOneWidget);
    });
  });

  group('with the protocol itself, on loopback', () {
    testWidgets('a code made on one device is copied to another', (
      tester,
    ) async {
      // `flutter_test` answers every HttpClient with a 400: this one test
      // talks to a real server, on this machine.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final network = PairNetwork(
        findAddress: () async => InternetAddress.loopbackIPv4,
      );
      // The sending device: its own container, its own settings.
      final senderScope = await settingsScopeOverrides(
        customize: (_) => pairFixtureSender(),
      );
      final sender = ProviderContainer(
        overrides: [
          ...senderScope,
          pairNetworkProvider.overrideWithValue(network),
        ],
      );
      addTearDown(sender.dispose);
      sender.listen(pairOfferProvider, (_, _) {});
      await tester.runAsync(
        () => sender
            .read(pairOfferProvider.notifier)
            .start(from: PairDevice.iphone),
      );
      final open = sender.read(pairOfferProvider) as PairOfferOpen;

      final receiver = await _pump(tester, network: network);
      await tester.enterText(_field(), open.link.toLink());
      // The fetch is a real request to the other container's server.
      for (var i = 0; i < 100; i++) {
        if (find.text('Add 4 services').evaluate().isNotEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.text('From your iPhone'), findsOneWidget);
      expect(sender.read(pairOfferProvider), isA<PairOfferSent>());

      await tester.tap(_filledButton('Add 4 services'));
      await tester.pumpAndSettle();
      expect(find.byKey(onboardingHomeStandIn), findsOneWidget);
      expect(receiver.read(currentSettingsProvider).instances, hasLength(4));
    });
  });

  group('an invite shown in person', () {
    testWidgets('while it opens: Your invite, and nothing of copying', (
      tester,
    ) async {
      final fixed = fixedReceive(const PairReceiveFetching(invite: true));
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Your invite'), findsOneWidget);
      expect(find.text('Opening the invite'), findsOneWidget);
      expect(find.text('Copy from another device'), findsNothing);
    });

    testWidgets('nothing arrived: its own words, and nothing here starts '
        'again', (tester) async {
      final fixed = fixedReceive(
        const PairReceiveFailed(PairReceiveFailure.expired, invite: true),
      );
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Your invite'), findsOneWidget);
      expect(find.text('This code has expired'), findsOneWidget);
      expect(find.text('Ask for a new one.'), findsOneWidget);
      expect(find.text('Start again'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('unreachable still offers Retry, the same code', (
      tester,
    ) async {
      final fixed = fixedReceive(
        const PairReceiveFailed(PairReceiveFailure.unreachable, invite: true),
      );
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Both need to be on the same Wi-Fi.'), findsOneWidget);
      await tester.tap(find.text(Lexicon.retry));
      expect(fixed.notifier.retries, 1);
      expect(find.text('Start again'), findsNothing);
    });

    testWidgets('what arrived wrong is the invite, said amber', (tester) async {
      final fixed = fixedReceive(
        const PairReceiveFailed(PairReceiveFailure.unreadable, invite: true),
      );
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Cupola could not read the invite'), findsOneWidget);
      expect(find.text('Ask for a new code.'), findsOneWidget);
    });

    testWidgets('Back from one that failed leaves, rather than wait for a '
        'link', (tester) async {
      final fixed = fixedReceive(
        const PairReceiveFailed(PairReceiveFailure.expired, invite: true),
      );
      await _pump(tester, overrides: [fixed.override]);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(fixed.notifier.resets, 0);
      expect(find.text('Welcome'), findsOneWidget);
    });

    testWidgets('arrived, with no Seerr here: on to the sign-in', (
      tester,
    ) async {
      final fixed = fixedReceive(const PairReceiveFetching(invite: true));
      await _pump(tester, overrides: [fixed.override]);

      fixed.notifier.show(const PairReceiveInvited());
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('arrived, with a Seerr signed in here: its account, and it '
        'says what changed', (tester) async {
      final fixed = fixedReceive(const PairReceiveFetching(invite: true));
      await _pump(tester, overrides: [fixed.override]);

      fixed.notifier.show(
        const PairReceiveInvited(
          here: ServiceInstance(
            id: 'mine',
            service: ServiceKey.seerr,
            url: 'http://192.168.1.10:5055',
            account: SeerrAccountSignIn(
              kind: SeerrAccountKind.local,
              userId: 4,
            ),
          ),
          updated: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Account mine'), findsOneWidget);
      expect(find.text('Updated from the invite'), findsOneWidget);
    });

    testWidgets('arrived, with a Seerr on the key here: its form, and '
        'nothing said when nothing changed', (tester) async {
      final fixed = fixedReceive(const PairReceiveFetching(invite: true));
      await _pump(tester, overrides: [fixed.override]);

      fixed.notifier.show(
        const PairReceiveInvited(
          here: ServiceInstance(
            id: 'seerr',
            service: ServiceKey.seerr,
            url: 'http://192.168.1.10:5055',
            credential: 'k',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seerr form seerr'), findsOneWidget);
      expect(find.text('Updated from the invite'), findsNothing);
    });
  });
}
