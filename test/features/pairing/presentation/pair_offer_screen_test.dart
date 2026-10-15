/// Set up another device, as the device that has everything sees it: the code
/// and what it holds, what each state of the code says and offers, and that
/// leaving the page closes it. Driven by fixed states where the words are the
/// point, and by the protocol itself, on loopback, where the code is.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/qr_code_view.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/pairing/data/pair_fetch.dart';
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/presentation/pair_offer_screen.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/pair_fixtures.dart';
import '../../../test_helpers/settings_scope.dart';

/// The page at `/settings/another-device`, opened from a stand-in Settings so
/// there is a page to go back to.
Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester, {
  SettingsModel? settings,
  PairNetwork network = const PairNetwork(),
  List<Override> overrides = const [],
  Size size = const Size(390, 2600),
}) async {
  final container = ProviderContainer(
    overrides: [
      ...await settingsScopeOverrides(
        customize: (_) => settings ?? pairFixtureSender(),
      ),
      pairNetworkProvider.overrideWithValue(network),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: ServiceRoutes.settings,
    routes: [
      GoRoute(
        path: ServiceRoutes.settings,
        builder: (_, _) => const Scaffold(body: Text('Settings')),
        routes: [
          GoRoute(
            path: 'another-device',
            builder: (_, _) => const PairOfferScreen(),
          ),
        ],
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
  await tester.pump();
  router.push(ServiceRoutes.settingsAnotherDevice);
  // Not settled: the page's progress and its countdown run for as long as it
  // is there.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return (container, router);
}

ColorScheme _scheme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(PairOfferScreen))).colorScheme;

Finder _slot() => find.byWidgetPredicate(
  (w) =>
      w is SizedBox &&
      w.width == PairOfferScreen.qrSide &&
      w.height == PairOfferScreen.qrSide,
);

Finder _filledButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<FilledButton>(),
);

PairOfferOpen _open({DateTime? closesAt, PairPackage? package}) =>
    PairOfferOpen(
      link: pairFixtureLink(closesAt: closesAt),
      package: package ?? pairFixturePackage(),
    );

String? _clipboard;

void _mockClipboard(WidgetTester tester) {
  _clipboard = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        _clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  group('the page', () {
    testWidgets('says what to do on the other phone, under its bar', (
      tester,
    ) async {
      final fixed = fixedOffer(const PairOfferPreparing());
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Set up another device'), findsOneWidget);
      expect(
        find.text(
          'On the other phone, open Cupola and choose Copy from another '
          'device.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('makes a code on its first frame, as the kind of device it '
        'is', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final fixed = fixedOffer(const PairOfferPreparing());
        await _pump(tester, overrides: [fixed.override]);

        expect(fixed.notifier.started, [PairDevice.iphone]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    for (final (platform, size, device) in [
      (TargetPlatform.iOS, const Size(820, 1180), PairDevice.ipad),
      (TargetPlatform.android, const Size(412, 915), PairDevice.androidPhone),
      (TargetPlatform.android, const Size(800, 1280), PairDevice.androidTablet),
      (TargetPlatform.macOS, const Size(1000, 900), PairDevice.mac),
    ]) {
      testWidgets('on ${platform.name} at ${size.width.toInt()}pt it is '
          '${device.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final fixed = fixedOffer(const PairOfferPreparing());
          await _pump(tester, overrides: [fixed.override], size: size);

          expect(fixed.notifier.started, [device]);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  group('preparing', () {
    testWidgets('holds the code\'s square with a quiet spinner, and the code '
        'takes the same place', (tester) async {
      final fixed = fixedOffer(const PairOfferPreparing());
      await _pump(tester, overrides: [fixed.override]);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(QrCodeView), findsNothing);
      final slotAt = tester.getTopLeft(_slot());
      expect(tester.getSize(_slot()), const Size.square(232));

      fixed.notifier.show(_open());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getTopLeft(find.byType(QrCodeView)), slotAt);
      expect(tester.getSize(find.byType(QrCodeView)), const Size.square(232));
    });

    testWidgets('says nothing of what moves yet', (tester) async {
      final fixed = fixedOffer(const PairOfferPreparing());
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('What moves'), findsNothing);
      expect(find.text("Why it's safe"), findsNothing);
      expect(find.text('Close the code now'), findsNothing);
    });
  });

  group('open', () {
    testWidgets('draws the link as a QR, says how to scan it, and how long it '
        'lasts', (tester) async {
      final open = _open();
      final fixed = fixedOffer(open);
      await _pump(
        tester,
        overrides: [fixed.override],
        network: PairNetwork(
          now: () => open.link.closesAt.subtract(
            const Duration(minutes: 1, seconds: 52),
          ),
        ),
      );

      expect(
        tester.widget<QrCodeView>(find.byType(QrCodeView)).data,
        open.link.toLink(),
      );
      expect(
        find.text('Scan with the camera on the other phone'),
        findsOneWidget,
      );
      expect(find.text('Closes in 1:52'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Close the code now'), findsOneWidget);
    });

    testWidgets('the countdown ticks each second, to zero, and is not a live '
        'region', (tester) async {
      final handle = tester.ensureSemantics();
      final open = _open();
      var left = const Duration(seconds: 3);
      final fixed = fixedOffer(open);
      await _pump(
        tester,
        overrides: [fixed.override],
        network: PairNetwork(now: () => open.link.closesAt.subtract(left)),
      );
      expect(find.text('Closes in 0:03'), findsOneWidget);

      for (final (seconds, words) in [
        (2, 'Closes in 0:02'),
        (1, 'Closes in 0:01'),
        (0, 'Closes in 0:00'),
        (-1, 'Closes in 0:00'),
      ]) {
        left = Duration(seconds: seconds);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text(words), findsOneWidget);
      }
      final node = tester.getSemantics(find.text('Closes in 0:00'));
      expect(node.flagsCollection.isLiveRegion, isFalse);
      handle.dispose();
    });

    testWidgets('Copy link copies the link and says so, then offers it '
        'again', (tester) async {
      _mockClipboard(tester);
      final open = _open();
      final fixed = fixedOffer(open);
      await _pump(tester, overrides: [fixed.override]);

      await tester.tap(find.text('Copy link'));
      await tester.pump();

      expect(_clipboard, open.link.toLink());
      expect(find.text('Link copied'), findsOneWidget);
      expect(find.text('Copy link'), findsNothing);

      await tester.pump(PairOfferScreen.copiedFor + const Duration(seconds: 1));
      expect(find.text('Copy link'), findsOneWidget);
    });

    const firewall =
        'If your Mac asks, allow Cupola to accept incoming connections.';

    testWidgets('names the Mac\'s firewall question on a Mac', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final fixed = fixedOffer(_open());
        await _pump(tester, overrides: [fixed.override]);
        expect(find.text(firewall), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('and not on ${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final fixed = fixedOffer(_open());
          await _pump(tester, overrides: [fixed.override]);
          expect(find.text(firewall), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('says what moves, in the order it moves, and nothing it does '
        'not', (tester) async {
      final fixed = fixedOffer(_open());
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('What moves'), findsOneWidget);
      for (final words in [
        '4 services and their keys',
        'Radarr, Sonarr, Seerr and qBittorrent',
        '1 trusted certificate',
        'So the new phone trusts the same servers you already trusted',
        'Seerr signs in again on the new phone',
        'A sign-in stays on the device it was made on',
        "qBittorrent's password stays behind",
        'This device could not read it. Paste it on the new phone.',
        'Encrypted, over your home network only',
        'Both phones need to be on your Wi-Fi',
      ]) {
        expect(find.text(words), findsOneWidget, reason: words);
      }
      expect(find.byIcon(Icons.key_rounded), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.key_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
    });

    testWidgets('leaves out what does not apply', (tester) async {
      final package = PairPackage(
        from: PairDevice.iphone,
        connections: const [
          ServiceInstance(
            id: 'radarr',
            service: ServiceKey.radarr,
            url: 'http://192.168.1.10:7878',
            credential: 'k',
          ),
        ],
      );
      final fixed = fixedOffer(_open(package: package));
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('1 service and its key'), findsOneWidget);
      expect(find.text('Radarr'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsNothing);
      expect(find.byIcon(Icons.person_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.key_off_rounded), findsNothing);
      expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
    });

    testWidgets('says why it is safe', (tester) async {
      final fixed = fixedOffer(_open());
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text("Why it's safe"), findsOneWidget);
      expect(
        find.text(
          'The code holds no secrets: only where to fetch them and the key to '
          'open them. It works once.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Close the code now closes it', (tester) async {
      final fixed = fixedOffer(_open());
      await _pump(tester, overrides: [fixed.override]);

      await tester.tap(find.text('Close the code now'));

      expect(fixed.notifier.closes, 1);
    });

    testWidgets('shows no secret, no address and no key, in any word it '
        'draws', (tester) async {
      final fixed = fixedOffer(_open());
      await _pump(tester, overrides: [fixed.override]);

      final words = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          t.data ?? t.textSpan?.toPlainText() ?? '',
      ].join(' ');
      for (final secret in [
        pairFixtureKey,
        'radarr-fixture-key',
        'seerr-fixture-session',
        'fixture-secret',
        '192.168.1',
        'radarr.home.arpa',
        pairFixturePin,
      ]) {
        expect(words, isNot(contains(secret)));
      }
    });

    testWidgets('the QR is an image with a label, and the rows speak one '
        'sentence', (tester) async {
      final handle = tester.ensureSemantics();
      final fixed = fixedOffer(_open());
      await _pump(tester, overrides: [fixed.override]);

      expect(
        find.bySemanticsLabel(RegExp('QR code to copy from this device')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^1 trusted certificate, So the new phone trusts the same '
            r'servers you already trusted$',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('once the other phone has it', () {
    testWidgets('a green check in the code\'s place, and Done leaves', (
      tester,
    ) async {
      final fixed = fixedOffer(PairOfferSent(pairFixturePackage()));
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Copied to the other phone'), findsOneWidget);
      expect(
        find.text('It has everything now. The code is closed.'),
        findsOneWidget,
      );
      expect(find.byType(QrCodeView), findsNothing);
      expect(find.text('What moves'), findsNothing);
      final scheme = _scheme(tester);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.check_rounded)).color,
        statusToneColor(
          scheme,
          StatusTone.success,
          surface: scheme.surfaceContainer,
        ),
      );
      expect(tester.getSize(_slot()), const Size.square(232));

      await tester.tap(_filledButton('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Copied to the other phone'), findsNothing);
    });
  });

  group('when the code closed', () {
    for (final (how, why) in [
      (PairServerEnd.expired, 'Its two minutes are up.'),
      (PairServerEnd.closed, "It can't be used any more."),
      (
        PairServerEnd.refused,
        'Something on your network asked for the wrong thing three times.',
      ),
    ]) {
      testWidgets('${how.name}: a neutral place, says why, and offers a new '
          'code', (tester) async {
        final fixed = fixedOffer(PairOfferClosed(how));
        await _pump(tester, overrides: [fixed.override]);

        expect(find.text('The code closed'), findsOneWidget);
        expect(find.text(why), findsOneWidget);
        expect(find.byType(QrCodeView), findsNothing);
        final scheme = _scheme(tester);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.qr_code_2_rounded)).color,
          statusToneColor(
            scheme,
            StatusTone.neutral,
            surface: scheme.surfaceContainer,
          ),
        );

        await tester.tap(_filledButton('Make a new code'));
        expect(fixed.notifier.starts, 2, reason: 'the first frame and this');
      });
    }
  });

  group('when no code can be made', () {
    testWidgets('no network is blue, informational, with Retry in ink', (
      tester,
    ) async {
      final fixed = fixedOffer(const PairOfferNoNetwork());
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Join your Wi-Fi to make a code'), findsOneWidget);
      expect(
        find.text('The other phone fetches everything over your home network.'),
        findsOneWidget,
      );
      final scheme = _scheme(tester);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.info_outline_rounded)).color,
        statusToneColor(scheme, StatusTone.info, surface: scheme.surface),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(QrCodeView), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, Lexicon.retry));
      expect(fixed.notifier.starts, 2);
    });

    testWidgets('a server that did not open is amber, with its one fill the '
        'remedy', (tester) async {
      final fixed = fixedOffer(const PairOfferFailed());
      await _pump(tester, overrides: [fixed.override]);

      expect(find.text('Cupola could not open the code'), findsOneWidget);
      expect(find.text('Wait a moment, then make a new code.'), findsOneWidget);
      final scheme = _scheme(tester);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded)).color,
        statusToneColor(scheme, StatusTone.warning, surface: scheme.surface),
      );
      expect(find.text(Lexicon.retry), findsNothing);

      await tester.tap(_filledButton('Make a new code'));
      expect(fixed.notifier.starts, 2);
    });
  });

  group('with the protocol itself, on loopback', () {
    PairNetwork onLoopback() =>
        PairNetwork(findAddress: () async => InternetAddress.loopbackIPv4);

    /// The page's server lives in the test's fake-async zone, so what it
    /// answers is delivered when the test pumps: real time passes between
    /// pumps, until the request [ask] makes is answered or refused.
    Future<T> answered<T>(WidgetTester tester, Future<T> Function() ask) async {
      T? value;
      Object? error;
      var done = false;
      ask().then(
        (v) {
          value = v;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      );
      for (var i = 0; i < 200 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      if (!done) fail('nothing answered');
      if (error != null) throw error!;
      return value as T;
    }

    Future<void> untilQr(WidgetTester tester) async {
      for (var i = 0; i < 200; i++) {
        if (find.byType(QrCodeView).evaluate().isNotEmpty) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      fail('no code');
    }

    void realNetwork(WidgetTester tester) {
      // `flutter_test` answers every HttpClient with a 400: these tests talk
      // to a real server, on this machine.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
    }

    testWidgets('shows the code, and says so when the other phone took it', (
      tester,
    ) async {
      realNetwork(tester);
      final (container, _) = await _pump(tester, network: onLoopback());
      await untilQr(tester);

      final data = tester.widget<QrCodeView>(find.byType(QrCodeView)).data;
      expect(data, startsWith('cupola://pair?'));
      expect(
        find.textContaining(RegExp(r'^Closes in [12]:\d\d$')),
        findsOneWidget,
      );

      final link = (container.read(pairOfferProvider) as PairOfferOpen).link;
      final package = await answered(
        tester,
        () => const PairNetwork().fetch(link),
      );
      expect(package.connections, hasLength(4));
      await tester.pump();

      expect(find.text('Copied to the other phone'), findsOneWidget);
      expect(find.byType(QrCodeView), findsNothing);
    });

    testWidgets('leaving the page closes the code', (tester) async {
      realNetwork(tester);
      final (container, router) = await _pump(tester, network: onLoopback());
      await untilQr(tester);
      final link = (container.read(pairOfferProvider) as PairOfferOpen).link;

      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      // The page's provider goes on the next tick of the clock, and the
      // server's own closing is delivered when the test pumps.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 25));
      }

      await expectLater(
        answered(tester, () => const PairNetwork().fetch(link)),
        throwsA(
          isA<PairFetchException>().having(
            (e) => e.failure,
            'failure',
            PairFetchFailure.unreachable,
          ),
        ),
      );
    });
  });
}
