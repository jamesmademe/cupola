import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/onboarding/presentation/widgets/onboarding_found.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/reel_finders.dart';
import '../../../test_helpers/settings_scope.dart';

/// Stand for keys wherever one would leak: nothing drawn or spoken may
/// contain them.
const _radarrKey = 'sentinel-radarr-key-5d1f';
const _radarr4kKey = 'sentinel-radarr4k-key-9c2e';
const _sonarrKey = 'sentinel-sonarr-key-3a7b';
const _pastedKey = 'sentinel-pasted-key-8e44';

const _seerr = CandidateSource(
  service: ServiceKey.seerr,
  connectionId: 'seerr',
  url: 'http://nas.home.arpa:5055',
);
const _prowlarr = CandidateSource(
  service: ServiceKey.prowlarr,
  connectionId: 'prowlarr',
  url: 'http://nas.home.arpa:9696',
);

ConnectionCandidate _radarr({
  String name = 'Radarr',
  String url = 'http://nas.home.arpa:7878',
  String? key = _radarrKey,
  String? externalUrl,
  CandidateSource source = _seerr,
}) => ConnectionCandidate(
  service: ServiceKey.radarr,
  name: name,
  reportedUrl: url,
  source: source,
  apiKey: key,
  externalUrl: externalUrl,
);

ConnectionCandidate _sonarr({
  String url = 'http://nas.home.arpa:8989',
  String? key = _sonarrKey,
  CandidateSource source = _seerr,
}) => ConnectionCandidate(
  service: ServiceKey.sonarr,
  name: 'Sonarr',
  reportedUrl: url,
  source: source,
  apiKey: key,
);

ServiceInstance _sourceInstance(CandidateSource source) => ServiceInstance(
  id: source.connectionId,
  service: source.service,
  url: source.url,
  credential: 'source-key',
);

ServiceDiagnosis _refused() => const ServiceDiagnosis(
  ServiceConnectionStatus.disconnected,
  ServiceFailureReason.unauthorized,
);

ServiceDiagnosis _silent() => const ServiceDiagnosis(
  ServiceConnectionStatus.disconnected,
  ServiceFailureReason.unreachable,
);

UntrustedCertificateProbe _probe({bool rotated = false, String hex = 'ab'}) => (
  certificate: ServerCertificate(
    fingerprint: hex * 32,
    subject: 'CN=nas.home.arpa',
    issuer: 'CN=nas.home.arpa',
  ),
  rotated: rotated,
);

ServiceDiagnosis _untrusted(UntrustedCertificateProbe probe) =>
    const ServiceDiagnosis(
      ServiceConnectionStatus.disconnected,
      ServiceFailureReason.tls,
    ).withCertificateProbe(probe);

/// What this device asked of a connection, as the widget's `diagnose` saw it.
typedef _Call = ({String url, String key, String? pin});

/// A `diagnose` the test answers for, by address. An address with no answer
/// of its own gets [fallback]; an answer can be a [Completer] the test
/// completes later, to see a row while it is trying.
class _Diagnose {
  ServiceDiagnosis fallback = const ServiceDiagnosis.connected();
  final Map<String, FutureOr<ServiceDiagnosis> Function(_Call call)> answers =
      {};
  final List<_Call> calls = [];

  void on(String url, FutureOr<ServiceDiagnosis> Function(_Call call) answer) {
    answers[url] = answer;
  }

  Future<ServiceDiagnosis> call(
    ServiceInstance instance,
    SettingsModel settings, {
    CertificateProber? probe,
  }) async {
    final call = (
      url: instance.url,
      key: instance.credential,
      pin: settings.pinForUrl(instance.url),
    );
    calls.add(call);
    final answer = answers[instance.url];
    return answer == null ? fallback : await answer(call);
  }

  List<String> get urls => [for (final c in calls) c.url];
}

class _Rig {
  _Rig({
    required this.tester,
    required this.diagnose,
    required this.added,
    required this.wentHome,
    required this.wentBack,
    required this.container,
  });

  final WidgetTester tester;
  final _Diagnose diagnose;
  final List<List<FoundConnection>> added;
  final List<bool> wentHome;
  final List<bool> wentBack;
  final ProviderContainer container;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  required List<ConnectionCandidate> known,
  CandidateSource source = _seerr,
  _Diagnose? diagnose,
  Widget? nothingKnownBody,
  Object? failure,
  List<ServiceKey> configured = const [],
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final overrides = <Override>[
    ...await settingsScopeOverrides(configured: configured),
    knownCandidatesProvider.overrideWith((ref, id) async {
      if (failure != null) throw failure;
      return known;
    }),
  ];
  final fake = diagnose ?? _Diagnose();
  final added = <List<FoundConnection>>[];
  final wentHome = <bool>[];
  final wentBack = <bool>[];
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            theme: AppTheme.darkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: OnboardingFound(
                  source: _sourceInstance(source),
                  nothingKnownBody: nothingKnownBody,
                  diagnose: fake.call,
                  certificateProber: (url, {pinnedFingerprint = ''}) async =>
                      null,
                  onAdd: (found) async => added.add(found),
                  onGoHome: () => wentHome.add(true),
                  onBack: () => wentBack.add(true),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  // The candidates arrive and each row is tried.
  await tester.pump();
  await tester.pump();
  return _Rig(
    tester: tester,
    diagnose: fake,
    added: added,
    wentHome: wentHome,
    wentBack: wentBack,
    container: container,
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Every string the screen draws.
Iterable<String> _drawn(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
];

void main() {
  group('the beat', () {
    testWidgets('names its step, the source and how many it knows', (
      tester,
    ) async {
      await _pump(
        tester,
        known: [
          _radarr(),
          _radarr(name: 'Radarr 4K'),
          _sonarr(),
        ],
      );

      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.text('Seerr knows 3 more services'), findsOneWidget);
      expect(
        find.text(
          'It already has their addresses and keys, so there is nothing to '
          'type.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('one service is said in the singular', (tester) async {
      await _pump(tester, known: [_radarr()]);

      expect(find.text('Seerr knows 1 more service'), findsOneWidget);
    });

    testWidgets('Prowlarr says it hides the keys', (tester) async {
      await _pump(
        tester,
        source: _prowlarr,
        known: [_radarr(key: null, source: _prowlarr)],
      );

      expect(find.text('Prowlarr knows 1 more service'), findsOneWidget);
      expect(
        find.text('Prowlarr hides keys: paste each one below.'),
        findsOneWidget,
      );
    });

    testWidgets('there is no way to skip: Back is the other way out', (
      tester,
    ) async {
      final rig = await _pump(tester, known: [_radarr()]);

      expect(find.textContaining('Skip'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();

      expect(rig.wentBack, [true]);
    });

    testWidgets('asks before it knows, and says who it asks', (tester) async {
      final completer = Completer<void>();
      await tester.binding.setSurfaceSize(const Size(390, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...await settingsScopeOverrides(),
            knownCandidatesProvider.overrideWith((ref, id) async {
              await completer.future;
              return [_radarr()];
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: Scaffold(
              body: OnboardingFound(
                source: _sourceInstance(_seerr),
                diagnose: _Diagnose().call,
                onAdd: (_) async {},
                onGoHome: () {},
                onBack: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Asking Seerr'), findsOneWidget);
      expect(findLine('Go to Home'), findsOneWidget);

      completer.complete();
      await _settle(tester);
      expect(find.text('Seerr knows 1 more service'), findsOneWidget);
    });
  });

  group('while it tries', () {
    testWidgets('each row says it is being tried from this device, with its '
        'address and its key', (tester) async {
      final diagnose = _Diagnose()
        ..on(
          'http://nas.home.arpa:7878',
          (_) => Completer<ServiceDiagnosis>().future,
        )
        ..on(
          'http://nas.home.arpa:8989',
          (_) => Completer<ServiceDiagnosis>().future,
        );
      await _pump(tester, known: [_radarr(), _sonarr()], diagnose: diagnose);

      expect(find.text('Trying from this device'), findsNWidgets(2));
      expect(find.text('nas.home.arpa:7878'), findsOneWidget);
      expect(find.text('nas.home.arpa:8989'), findsOneWidget);
      expect(find.text('key included'), findsNWidgets(2));
      // Nothing has answered, so there is nothing to add yet.
      expect(findLine('Go to Home'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('each is tried at the proposal, with the source key, and '
        'nothing is sent twice', (tester) async {
      final diagnose = _Diagnose();
      await _pump(tester, known: [_radarr(), _sonarr()], diagnose: diagnose);

      expect(diagnose.calls, [
        (url: 'http://nas.home.arpa:7878', key: _radarrKey, pin: null),
        (url: 'http://nas.home.arpa:8989', key: _sonarrKey, pin: null),
      ]);
    });

    testWidgets('the count grows as they answer', (tester) async {
      final radarr = Completer<ServiceDiagnosis>();
      final sonarr = Completer<ServiceDiagnosis>();
      final diagnose = _Diagnose()
        ..on('http://nas.home.arpa:7878', (_) => radarr.future)
        ..on('http://nas.home.arpa:8989', (_) => sonarr.future);
      await _pump(tester, known: [_radarr(), _sonarr()], diagnose: diagnose);
      expect(findLine('Go to Home'), findsOneWidget);

      radarr.complete(const ServiceDiagnosis.connected());
      await _settle(tester);
      expect(findLine('Add 1 service'), findsOneWidget);
      expect(find.text('Answering'), findsOneWidget);
      expect(find.text('Trying from this device'), findsOneWidget);

      sonarr.complete(const ServiceDiagnosis.connected());
      await _settle(tester);
      expect(findLine('Add 2 services'), findsOneWidget);
    });

    testWidgets('a row that answered is on, and can be switched off', (
      tester,
    ) async {
      await _pump(tester, known: [_radarr(), _sonarr()]);
      await _settle(tester);
      expect(findLine('Add 2 services'), findsOneWidget);
      expect(
        [
          for (final s in tester.widgetList<Switch>(find.byType(Switch)))
            s.value,
        ],
        [true, true],
      );

      await tester.tap(find.byType(Switch).first);
      await _settle(tester);

      expect(findLine('Add 1 service'), findsOneWidget);
      await tester.tap(find.byType(Switch).last);
      await _settle(tester);
      expect(findLine('Go to Home'), findsOneWidget);
    });
  });

  group('adding', () {
    testWidgets('hands over what answered and is on, ready to save', (
      tester,
    ) async {
      final rig = await _pump(
        tester,
        known: [
          _radarr(),
          _radarr(
            name: 'Radarr 4K',
            url: 'http://nas.home.arpa:7879',
            key: _radarr4kKey,
          ),
          _sonarr(),
        ],
      );
      await _settle(tester);
      await tester.tap(find.byType(Switch).at(1));
      await _settle(tester);

      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);

      expect(rig.added, hasLength(1));
      final [radarr, sonarr] = rig.added.single;
      expect(radarr.instance.service, ServiceKey.radarr);
      expect(radarr.instance.id, 'radarr');
      expect(radarr.instance.url, 'http://nas.home.arpa:7878');
      expect(radarr.instance.credential, _radarrKey);
      // Named as the service is: no label.
      expect(radarr.instance.label, '');
      expect(radarr.certFingerprint, isNull);
      expect(sonarr.instance.service, ServiceKey.sonarr);
      expect(sonarr.instance.id, 'sonarr');
      expect(sonarr.instance.credential, _sonarrKey);
    });

    testWidgets('a name other than the service is its label, and ids avoid '
        'the saved ones', (tester) async {
      final rig = await _pump(
        tester,
        known: [_radarr(name: 'Radarr 4K', url: 'https://nas.home.arpa:7879')],
        configured: [ServiceKey.radarr],
      );
      await _settle(tester);

      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);

      final connection = rig.added.single.single;
      expect(connection.instance.label, 'Radarr 4K');
      expect(connection.instance.id, isNot('radarr'));
      expect(connection.instance.id, startsWith('radarr-'));
    });

    testWidgets('saves nothing itself', (tester) async {
      final rig = await _pump(tester, known: [_radarr(), _sonarr()]);
      await _settle(tester);
      final before = rig.container.read(currentSettingsProvider);

      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);

      expect(rig.container.read(currentSettingsProvider), same(before));
    });

    testWidgets('with nothing that answered, the exit is Go to Home and adds '
        'nothing', (tester) async {
      final diagnose = _Diagnose()..fallback = _silent();
      final rig = await _pump(
        tester,
        known: [_radarr(), _sonarr()],
        diagnose: diagnose,
      );
      await _settle(tester);

      await tester.tap(find.byType(ReelCommandButton));
      await tester.pump();

      expect(rig.wentHome, [true]);
      expect(rig.added, isEmpty);
    });
  });

  group('a row that did not answer', () {
    testWidgets('says so in its row, in red, and the others still join', (
      tester,
    ) async {
      final diagnose = _Diagnose()
        ..on('http://nas.home.arpa:8989', (_) => _silent());
      final rig = await _pump(
        tester,
        known: [_radarr(), _sonarr()],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(
        find.text(
          'Sonarr did not answer at nas.home.arpa:8989 from this device',
        ),
        findsOneWidget,
      );
      expect(find.text('Answering'), findsOneWidget);
      expect(findLine('Add 1 service'), findsOneWidget);
      // The fault is its own row's: the headline and the exit carry on.
      expect(find.text('Seerr knows 2 more services'), findsOneWidget);

      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);
      expect(
        [for (final c in rig.added.single) c.instance.service],
        [ServiceKey.radarr],
      );
    });

    testWidgets('red wears a ghost Retry, in ink, and asking again can '
        'bring it in', (tester) async {
      final diagnose = _Diagnose()
        ..on('http://nas.home.arpa:8989', (_) => _silent());
      await _pump(tester, known: [_sonarr()], diagnose: diagnose);
      await _settle(tester);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);

      diagnose.answers.clear();
      await tester.tap(find.text('Retry'));
      await _settle(tester);

      expect(find.text('Answering'), findsOneWidget);
      expect(findLine('Add 1 service'), findsOneWidget);
      expect(diagnose.urls, hasLength(2));
    });

    testWidgets('an amber fault with nothing to fix but asking again offers '
        'Retry as its one fill', (tester) async {
      final diagnose = _Diagnose()
        ..fallback = const ServiceDiagnosis(
          ServiceConnectionStatus.disconnected,
          ServiceFailureReason.serverError,
        );
      await _pump(tester, known: [_sonarr()], diagnose: diagnose);
      await _settle(tester);

      expect(find.text('Sonarr answered with an error'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('a gateway in front of it offers nothing this screen cannot '
        'do', (tester) async {
      final diagnose = _Diagnose()
        ..fallback = const ServiceDiagnosis(
          ServiceConnectionStatus.disconnected,
          ServiceFailureReason.accessGateway,
        );
      await _pump(tester, known: [_sonarr()], diagnose: diagnose);
      await _settle(tester);

      expect(
        find.text('Something in front of Sonarr answered instead of it'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      // Nothing in the row but its sentence: the one button is the exit's.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(findLine('Go to Home'), findsOneWidget);
    });
  });

  group('a key refused at the proposed address', () {
    ConnectionCandidate radarr4kInDocker() => _radarr(
      name: 'Radarr 4K',
      url: 'http://radarr-4k:7878',
      key: _radarr4kKey,
    );

    _Diagnose refusingTheFirstRadarrsAddress() => _Diagnose()
      ..on(
        'http://nas.home.arpa:7878',
        (call) => call.key == _radarr4kKey
            ? _refused()
            : const ServiceDiagnosis.connected(),
      );

    testWidgets('is amber, names the address, and leads with the remedy', (
      tester,
    ) async {
      await _pump(
        tester,
        known: [radarr4kInDocker()],
        diagnose: refusingTheFirstRadarrsAddress(),
      );
      await _settle(tester);

      expect(
        find.text("nas.home.arpa:7878 answered but refused Radarr 4K's key"),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Type its address'),
        findsOneWidget,
      );
      // The same key can only be refused again: no Retry beside the remedy.
      expect(find.text('Retry'), findsNothing);
      expect(findLine('Go to Home'), findsOneWidget);
    });

    testWidgets('Type its address opens a field in the row, and what is typed '
        'is tried with the same key', (tester) async {
      final diagnose = refusingTheFirstRadarrsAddress();
      final rig = await _pump(
        tester,
        known: [radarr4kInDocker()],
        diagnose: diagnose,
      );
      await _settle(tester);

      await tester.tap(find.text('Type its address'));
      await tester.pump();
      // The field is the remedy taken: the button gives way to it.
      expect(find.text('Type its address'), findsNothing);
      final field = find.widgetWithText(TextField, '');
      expect(find.text("Radarr 4K's address"), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'https://nas.home.arpa:7879',
      );
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await _settle(tester);

      expect(field, findsNothing);
      expect(diagnose.calls.last, (
        url: 'https://nas.home.arpa:7879',
        key: _radarr4kKey,
        pin: null,
      ));
      expect(find.text('Answering'), findsOneWidget);
      expect(find.text('nas.home.arpa:7879 · https'), findsOneWidget);
      // What the person typed is not the source's guess: the found address
      // is no longer printed.
      expect(find.textContaining('own host'), findsNothing);
      expect(findLine('Add 1 service'), findsOneWidget);

      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);
      expect(
        rig.added.single.single.instance.url,
        'https://nas.home.arpa:7879',
      );
      expect(rig.added.single.single.instance.credential, _radarr4kKey);
    });

    testWidgets('says why the address was only a guess', (tester) async {
      await _pump(
        tester,
        known: [radarr4kInDocker()],
        diagnose: refusingTheFirstRadarrsAddress(),
      );
      await _settle(tester);

      expect(
        find.textContaining("own host with Radarr 4K's port"),
        findsOneWidget,
      );
    });
  });

  group('a name inside Docker', () {
    testWidgets("is proposed on the source's host, and the found address is "
        'always printed', (tester) async {
      final diagnose = _Diagnose();
      await _pump(
        tester,
        known: [
          _radarr(url: 'http://radarr:7878'),
          _sonarr(url: 'http://sonarr:8989'),
        ],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(diagnose.urls, [
        'http://nas.home.arpa:7878',
        'http://nas.home.arpa:8989',
      ]);
      expect(find.text('nas.home.arpa:7878'), findsOneWidget);
      expect(
        find.text(
          "Seerr has radarr:7878 · Seerr's own host, with Radarr's port",
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "Seerr has sonarr:8989 · Seerr's own host, with Sonarr's port",
        ),
        findsOneWidget,
      );
      expect(
        find.text('Seerr reaches them by their names inside Docker.'),
        findsOneWidget,
      );
    });

    testWidgets('an address this device reaches is not explained', (
      tester,
    ) async {
      await _pump(tester, known: [_radarr(), _sonarr()]);
      await _settle(tester);

      expect(find.textContaining('own host'), findsNothing);
    });
  });

  group('a certificate', () {
    ConnectionCandidate radarr4k() => _radarr(
      name: 'Radarr 4K',
      url: 'https://nas.home.arpa:7879',
      key: _radarr4kKey,
    );

    _Diagnose selfSigned({bool rotated = false}) => _Diagnose()
      ..on(
        'https://nas.home.arpa:7879',
        (call) => call.pin == null
            ? _untrusted(_probe(rotated: rotated))
            : const ServiceDiagnosis.connected(),
      );

    testWidgets('is asked inline, with its fingerprint, and the row waits for '
        'the person', (tester) async {
      await _pump(
        tester,
        known: [radarr4k(), _sonarr()],
        diagnose: selfSigned(),
      );
      await _settle(tester);

      // Said once, by the row.
      expect(find.text('Waiting for you'), findsOneWidget);
      expect(
        find.text('Radarr 4K uses a self-signed certificate'),
        findsOneWidget,
      );
      // The whole fingerprint, in lines of eight bytes: it is compared by eye.
      expect(find.text('SHA-256'), findsOneWidget);
      expect(
        find.text(List.filled(4, List.filled(8, 'AB').join(':')).join('\n')),
        findsOneWidget,
      );
      expect(find.text('Trust'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      // The other row joined on its own, and the exit counts only it.
      expect(findLine('Add 1 service'), findsOneWidget);
    });

    testWidgets('joins once trusted, and the pin goes with it', (tester) async {
      final diagnose = selfSigned();
      final rig = await _pump(tester, known: [radarr4k()], diagnose: diagnose);
      await _settle(tester);

      await tester.tap(find.text('Trust'));
      await _settle(tester);

      expect(find.text('Answering'), findsOneWidget);
      expect(diagnose.calls.last.pin, _probe().certificate.fingerprint);
      expect(find.text('Waiting for you'), findsNothing);

      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);
      expect(
        rig.added.single.single.certFingerprint,
        _probe().certificate.fingerprint,
      );
    });

    testWidgets('one decision covers every row at the same origin', (
      tester,
    ) async {
      final diagnose = _Diagnose()
        ..on(
          'https://nas.home.arpa:7879',
          (call) => call.pin == null
              ? _untrusted(_probe())
              : const ServiceDiagnosis.connected(),
        );
      await _pump(
        tester,
        known: [
          radarr4k(),
          _sonarr(url: 'https://nas.home.arpa:7879'),
        ],
        diagnose: diagnose,
      );
      await _settle(tester);
      expect(find.text('Trust'), findsNWidgets(2));

      await tester.tap(find.text('Trust').first);
      await _settle(tester);

      expect(find.text('Answering'), findsNWidgets(2));
      expect(find.text('Trust'), findsNothing);
    });

    testWidgets('Not now keeps it out, and its remedy brings it back', (
      tester,
    ) async {
      await _pump(tester, known: [radarr4k()], diagnose: selfSigned());
      await _settle(tester);

      await tester.tap(find.text('Not now'));
      await _settle(tester);

      expect(find.text('Waiting for you'), findsNothing);
      expect(
        find.text('Radarr 4K has a certificate Cupola does not trust'),
        findsOneWidget,
      );
      expect(findLine('Go to Home'), findsOneWidget);

      await tester.tap(find.text('Check the certificate'));
      await _settle(tester);
      expect(find.text('Trust'), findsOneWidget);
    });

    testWidgets('a certificate that changed is the escalation, never a '
        'routine prompt', (tester) async {
      await _pump(
        tester,
        known: [radarr4k()],
        diagnose: selfSigned(rotated: true),
      );
      await _settle(tester);

      expect(find.text('This certificate has changed'), findsOneWidget);
      expect(find.text('Trust this certificate anyway'), findsOneWidget);
      expect(
        find.text('Radarr 4K uses a self-signed certificate'),
        findsNothing,
      );
    });
  });

  group('Prowlarr, which hides its keys', () {
    ConnectionCandidate radarr4k() => _radarr(
      name: 'Radarr 4K',
      url: 'http://radarr-4k:7878',
      key: null,
      source: _prowlarr,
    );

    void clipboardSays(WidgetTester tester, String text) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{'text': text}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    testWidgets('a row with no key asks for it, and is tried once it is in', (
      tester,
    ) async {
      final diagnose = _Diagnose();
      await _pump(
        tester,
        source: _prowlarr,
        known: [radarr4k()],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(diagnose.calls, isEmpty);
      expect(find.text('Prowlarr shows ********'), findsOneWidget);
      expect(find.text("Radarr 4K's API key"), findsOneWidget);
      expect(
        find.text('In Radarr 4K: Settings › General › Security'),
        findsOneWidget,
      );
      expect(find.text('Trying from this device'), findsNothing);
      expect(findLine('Go to Home'), findsOneWidget);
    });

    testWidgets('Paste puts the key in and tries it', (tester) async {
      clipboardSays(tester, '  $_pastedKey ');
      final diagnose = _Diagnose();
      final rig = await _pump(
        tester,
        source: _prowlarr,
        known: [radarr4k()],
        diagnose: diagnose,
      );
      await _settle(tester);

      await tester.tap(find.byTooltip('Paste'));
      await _settle(tester);

      expect(diagnose.calls, [
        (url: 'http://nas.home.arpa:7878', key: _pastedKey, pin: null),
      ]);
      expect(find.text('key pasted'), findsOneWidget);
      expect(find.text('Answering'), findsOneWidget);
      expect(find.text("Radarr 4K's API key"), findsNothing);
      expect(findLine('Add 1 service'), findsOneWidget);

      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);
      expect(rig.added.single.single.instance.credential, _pastedKey);
    });

    testWidgets('a typed key is tried when it is sent', (tester) async {
      final diagnose = _Diagnose();
      await _pump(
        tester,
        source: _prowlarr,
        known: [radarr4k()],
        diagnose: diagnose,
      );
      await _settle(tester);

      await tester.enterText(find.byType(TextField), _pastedKey);
      expect(diagnose.calls, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);

      expect(diagnose.calls.single.key, _pastedKey);
      expect(find.text('Answering'), findsOneWidget);
    });

    testWidgets('a pasted key that is refused leaves its field to paste '
        'another, and its address to type', (tester) async {
      clipboardSays(tester, _pastedKey);
      final diagnose = _Diagnose()..fallback = _refused();
      await _pump(
        tester,
        source: _prowlarr,
        known: [radarr4k()],
        diagnose: diagnose,
      );
      await _settle(tester);

      await tester.tap(find.byTooltip('Paste'));
      await _settle(tester);

      expect(
        find.text("nas.home.arpa:7878 answered but refused Radarr 4K's key"),
        findsOneWidget,
      );
      expect(find.text("Radarr 4K's API key"), findsOneWidget);
      expect(find.text('Type its address'), findsOneWidget);
    });
  });

  group('the External URL', () {
    ConnectionCandidate withExternal(String name, String external) => _radarr(
      name: name,
      url: name == 'Radarr'
          ? 'http://nas.home.arpa:7878'
          : 'http://nas.home.arpa:7879',
      key: name == 'Radarr' ? _radarrKey : _radarr4kKey,
      externalUrl: external,
    );

    testWidgets('becomes the address away only when it accepts the key', (
      tester,
    ) async {
      final diagnose = _Diagnose()
        ..on('https://radarr-4k.example.com', (_) => _refused());
      final rig = await _pump(
        tester,
        known: [
          withExternal('Radarr', 'https://radarr.example.com/'),
          withExternal('Radarr 4K', 'https://radarr-4k.example.com'),
        ],
        diagnose: diagnose,
      );
      await _settle(tester);
      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);

      final [radarr, radarr4k] = rig.added.single;
      expect(radarr.instance.away?.url, 'https://radarr.example.com');
      expect(radarr4k.instance.away, isNull);
      expect(
        diagnose.calls.where((c) => c.url == 'https://radarr.example.com'),
        [(url: 'https://radarr.example.com', key: _radarrKey, pin: null)],
      );
    });

    testWidgets('never holds the row: it answers before the other address '
        'does', (tester) async {
      final away = Completer<ServiceDiagnosis>();
      final diagnose = _Diagnose()
        ..on('https://radarr.example.com', (_) => away.future);
      final rig = await _pump(
        tester,
        known: [withExternal('Radarr', 'https://radarr.example.com')],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(find.text('Answering'), findsOneWidget);
      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);

      expect(rig.added.single.single.instance.away, isNull);
      away.complete(const ServiceDiagnosis.connected());
      await tester.pump();
    });

    testWidgets('is not asked at an address that would send the key in the '
        'clear off the local network', (tester) async {
      final diagnose = _Diagnose();
      final rig = await _pump(
        tester,
        known: [withExternal('Radarr', 'http://radarr.example.com')],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(diagnose.urls, ['http://nas.home.arpa:7878']);
      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);
      expect(rig.added.single.single.instance.away, isNull);
    });

    testWidgets('the address already tried is not tried again', (tester) async {
      final diagnose = _Diagnose();
      await _pump(
        tester,
        known: [withExternal('Radarr', 'http://nas.home.arpa:7878/')],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(diagnose.urls, ['http://nas.home.arpa:7878']);
    });
  });

  group('the key never leaves the device in the clear', () {
    testWidgets('an address off the local network over http is not tried, '
        'and says why', (tester) async {
      final diagnose = _Diagnose();
      await _pump(
        tester,
        known: [_radarr(url: 'http://radarr.example.com:7878')],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(diagnose.calls, isEmpty);
      expect(find.text('Radarr needs an https:// address'), findsOneWidget);
      expect(find.text('Change the address'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('a source that knows nothing', () {
    testWidgets('says so, and the exit is Go to Home', (tester) async {
      final rig = await _pump(
        tester,
        known: const [],
        nothingKnownBody: const Text('the list of services to add'),
      );
      await _settle(tester);

      expect(
        find.text("Seerr doesn't know any other service yet"),
        findsOneWidget,
      );
      expect(
        find.text(
          'Seerr is set up. Add the others one at a time: each asks for its '
          'address and key.',
        ),
        findsOneWidget,
      );
      expect(find.text('the list of services to add'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);

      await tester.tap(find.byType(ReelCommandButton));
      await tester.pump();
      expect(rig.wentHome, [true]);
      expect(rig.added, isEmpty);
    });

    testWidgets('Prowlarr is named the same way', (tester) async {
      await _pump(tester, source: _prowlarr, known: const []);

      expect(
        find.text("Prowlarr doesn't know any other service yet"),
        findsOneWidget,
      );
    });
  });

  group('a source that did not answer', () {
    testWidgets('is said in the source\'s own words, with a ghost Retry, and '
        'Go to Home is still the way out', (tester) async {
      final rig = await _pump(
        tester,
        known: const [],
        failure: DioException(
          requestOptions: RequestOptions(path: '/api/v1/settings/radarr'),
          type: DioExceptionType.connectionError,
        ),
      );
      await _settle(tester);

      expect(find.text('Seerr did not answer'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      await tester.tap(find.byType(ReelCommandButton));
      await tester.pump();
      expect(rig.wentHome, [true]);
    });
  });

  group('at twice the reading size', () {
    testWidgets('every state still fits, and the exit stays', (tester) async {
      final diagnose = _Diagnose()
        ..on('http://nas.home.arpa:8989', (_) => _silent())
        ..on('https://nas.home.arpa:7879', (call) => _untrusted(_probe()))
        ..on(
          'http://nas.home.arpa:7878',
          (call) => call.key == _radarr4kKey
              ? _refused()
              : const ServiceDiagnosis.connected(),
        );
      await _pump(
        tester,
        textScale: 2,
        diagnose: diagnose,
        known: [
          _radarr(),
          _radarr(
            name: 'Radarr 4K',
            url: 'http://radarr-4k:7878',
            key: _radarr4kKey,
          ),
          _radarr(
            name: 'Radarr Anime',
            url: 'https://nas.home.arpa:7879',
            key: _radarr4kKey,
          ),
          _sonarr(),
          _radarr(name: 'Radarr Kids', key: null, source: _prowlarr),
        ],
      );
      await _settle(tester);

      // An overflow is an exception in a test: reaching here is the check.
      expect(tester.takeException(), isNull);
      expect(find.byType(ReelCommandButton), findsOneWidget);
    });
  });

  group('what the screen says, and never says', () {
    testWidgets('a row speaks one sentence, and its controls stay their own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final diagnose = _Diagnose()
        ..on('http://nas.home.arpa:8989', (_) => _silent());
      await _pump(
        tester,
        known: [
          _radarr(name: 'Radarr 4K', url: 'https://nas.home.arpa:7879'),
          _sonarr(),
        ],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(
        find.bySemanticsLabel(
          'Radarr 4K, nas.home.arpa:7879 · https, key included. Answering',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Sonarr, nas.home.arpa:8989, key included. Sonarr did not answer at '
          'nas.home.arpa:8989 from this device',
        ),
        findsOneWidget,
      );
      // The parts are silenced under the sentence.
      expect(find.bySemanticsLabel('key included'), findsNothing);
      // The controls are their own.
      expect(find.bySemanticsLabel('Add Radarr 4K'), findsOneWidget);
      expect(find.bySemanticsLabel('Retry Sonarr'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a remedy and a certificate decision name their row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final diagnose = _Diagnose()
        ..on('http://nas.home.arpa:7878', (_) => _refused())
        ..on('https://nas.home.arpa:7879', (_) => _untrusted(_probe()));
      await _pump(
        tester,
        known: [
          _radarr(),
          _radarr(
            name: 'Radarr 4K',
            url: 'https://nas.home.arpa:7879',
            key: _radarr4kKey,
          ),
        ],
        diagnose: diagnose,
      );
      await _settle(tester);

      expect(find.bySemanticsLabel('Type its address for Radarr'), findsOne);
      expect(
        find.bySemanticsLabel('Trust the certificate of Radarr 4K'),
        findsOne,
      );
      expect(find.bySemanticsLabel('Not now for Radarr 4K'), findsOne);
      handle.dispose();
    });

    testWidgets('a Docker row says where the source has it', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, known: [_radarr(url: 'http://radarr:7878')]);
      await _settle(tester);

      expect(
        find.bySemanticsLabel(
          "Radarr, nas.home.arpa:7878, key included. Seerr has radarr:7878 · "
          "Seerr's own host, with Radarr's port. Answering",
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a key is in nothing drawn, spoken or printed', (tester) async {
      final handle = tester.ensureSemantics();
      final diagnose = _Diagnose()
        ..on('http://nas.home.arpa:7879', (_) => _refused());
      final rig = await _pump(
        tester,
        known: [
          _radarr(),
          _radarr(
            name: 'Radarr 4K',
            url: 'http://nas.home.arpa:7879',
            key: _radarr4kKey,
          ),
          _sonarr(),
        ],
        diagnose: diagnose,
      );
      await _settle(tester);
      await tester.tap(find.byType(ReelCommandButton));
      await _settle(tester);

      final keys = [_radarrKey, _radarr4kKey, _sonarrKey];
      final everything = [
        ..._drawn(tester),
        tester.getSemantics(find.byType(OnboardingFound)).toString(),
        for (final connection in rig.added.expand((f) => f))
          connection.toString(),
      ].join('\n');
      for (final key in keys) {
        expect(everything, isNot(contains(key)));
      }
      handle.dispose();
    });
  });

  group('over the profiles, with the app\'s own clients', () {
    Future<_Rig> pumpProfile(
      WidgetTester tester,
      ProfileHarness harness,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      harness.network.followFakeTime(tester.binding);
      final added = <List<FoundConnection>>[];
      final wentHome = <bool>[];
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.darkTheme(),
                home: Scaffold(
                  body: OnboardingFound(
                    source: harness.profile.connection(WorldIds.seerr).instance,
                    certificateProber: (url, {pinnedFingerprint = ''}) async =>
                        null,
                    onAdd: (found) async => added.add(found),
                    onGoHome: () => wentHome.add(true),
                    onBack: () {},
                  ),
                ),
              );
            },
          ),
        ),
      );
      await harness.settle(tester);
      return _Rig(
        tester: tester,
        diagnose: _Diagnose(),
        added: added,
        wentHome: wentHome,
        wentBack: [],
        container: container,
      );
    }

    testWidgets('P5: Seerr knows a Radarr and a Sonarr, both answer at their '
        'addresses and join in one tap', (tester) async {
      final harness = await ProfileHarness.start(Profiles.p5);
      final rig = await pumpProfile(tester, harness);

      expect(find.text('Seerr knows 2 more services'), findsOneWidget);
      expect(find.text('Answering'), findsNWidgets(2));
      expect(findLine('Add 2 services'), findsOneWidget);

      await tester.tap(find.byType(ReelCommandButton));
      await harness.settle(tester);

      final [radarr, sonarr] = rig.added.single;
      expect(radarr.instance.url, WorldHosts.radarr);
      expect(radarr.instance.credential, worldKey(WorldIds.radarr));
      expect(sonarr.instance.url, WorldHosts.sonarr);
      expect(sonarr.instance.credential, worldKey(WorldIds.sonarr));
      // The key travelled in the header of the request this device made to
      // the arr, and went nowhere else.
      expect(
        harness.network
            .requestsTo('seerr-known-radarr-0')
            .map((r) => r.headers['x-api-key'])
            .toSet(),
        {worldKey(WorldIds.radarr)},
      );
      await harness.unmount(tester);
    });

    testWidgets('P5: a Sonarr that does not answer stays in its row', (
      tester,
    ) async {
      final harness = await ProfileHarness.start(Profiles.p5);
      harness.network.behave(
        'seerr-known-sonarr-0',
        ConnectionBehaviour.didNotAnswer,
      );
      await pumpProfile(tester, harness);

      expect(
        find.text(
          'Sonarr did not answer at nas.home.arpa:8989 from this device',
        ),
        findsOneWidget,
      );
      expect(find.text('Answering'), findsOneWidget);
      expect(findLine('Add 1 service'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('P5: a Radarr that refuses the key is amber, with its '
        'remedy', (tester) async {
      final harness = await ProfileHarness.start(Profiles.p5);
      harness.network.behave(
        'seerr-known-radarr-0',
        ConnectionBehaviour.refusesKey,
      );
      await pumpProfile(tester, harness);

      expect(
        find.text("nas.home.arpa:7878 answered but refused Radarr's key"),
        findsOneWidget,
      );
      expect(find.text('Type its address'), findsOneWidget);
      expect(findLine('Add 1 service'), findsOneWidget);
      await harness.unmount(tester);
    });

    testWidgets('P5 on Docker: the names Seerr uses are proposed on its host, '
        'and answer there', (tester) async {
      final harness = await ProfileHarness.start(
        Profiles.p5.withDockerHostnames(),
      );
      await pumpProfile(tester, harness);

      expect(
        find.text('Seerr reaches them by their names inside Docker.'),
        findsOneWidget,
      );
      expect(find.text('Answering'), findsNWidgets(2));
      expect(harness.network.unanswered, isEmpty);
      await harness.unmount(tester);
    });
  });
}
