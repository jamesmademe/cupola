/// The operator's invite sheet: the QR and the link of one Seerr connection,
/// what the invite cannot do said under it, and nothing secret in either.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/qr_code_view.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/invite_sheet.dart';

import '../../../../test_helpers/semantics_announcements.dart';
import '../../../../test_helpers/settings_scope.dart';

const _id = 'seerr';
const _home = 'https://nas.home.arpa:5055';
const _away = 'https://seerr.example.net';

const _homeGate =
    'The address at home asks for a token, and an invite never carries one.';
const _homeOnly = 'It works at home: Seerr has no address away from home.';
const _awayGate =
    'It works at home: the address away asks for a token, and an invite never '
    'carries one.';

ServiceInstance _seerr({
  ConnectionAccess access = const NoAccess(),
  ConnectionAddress? away = const ConnectionAddress(url: _away),
}) => ServiceInstance(
  id: _id,
  service: ServiceKey.seerr,
  url: _home,
  credential: 'sentinel-key',
  access: access,
  away: away,
);

SeerrServerFacts _facts({String? title = 'Rossi Movies'}) =>
    SeerrServerFacts.fromPublicSettings({
      'initialized': true,
      'applicationTitle': ?title,
    });

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

/// The sheet open over a page, on a phone, for [connection], whose server
/// answers with what [facts] says.
Future<ProviderContainer> _open(
  WidgetTester tester,
  ServiceInstance connection, {
  Future<SeerrServerFacts> Function()? facts,
}) async {
  final overrides = await settingsScopeOverrides(
    customize: (_) => SettingsModel(instances: [connection]),
  );
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        seerrServerFactsProvider.overrideWith(
          (ref, id) => (facts ?? () async => _facts())(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInviteSheet(context, connectionId: _id),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  // The sheet rises, and the facts arrive. No settle: while the facts wait, a
  // placeholder sweeps for ever.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

String _qrData(WidgetTester tester) =>
    tester.widget<QrCodeView>(find.byType(QrCodeView)).data;

void main() {
  testWidgets('shows the invite as a QR, with the server\'s name and host', (
    tester,
  ) async {
    await _open(tester, _seerr());

    expect(find.text('Invite someone'), findsOneWidget);
    expect(
      find.text(
        'They scan this with their phone\'s camera and sign in to Seerr with '
        'their own account.',
      ),
      findsOneWidget,
    );
    expect(find.byType(QrCodeView), findsOneWidget);
    expect(tester.getSize(find.byType(QrCodeView)), const Size.square(232));
    expect(find.text('Rossi Movies · nas.home.arpa:5055'), findsOneWidget);
    expect(
      find.text(
        'Sent as a message, they paste it where Cupola asks where their '
        'Seerr is.',
      ),
      findsOneWidget,
    );

    // The QR says what the link says, made of the saved connection alone:
    // the server's name is on the screen and in no link.
    final expected = SeerrInvite.of(
      _seerr(),
      SettingsModel(instances: [_seerr()]),
    ).toLink();
    expect(_qrData(tester), expected);
    expect(Uri.parse(expected).queryParameters['away'], _away);
    expect(Uri.parse(expected).queryParameters, isNot(contains('title')));
  });

  testWidgets('a server with no name of its own is read by its host alone', (
    tester,
  ) async {
    await _open(tester, _seerr(), facts: () async => _facts(title: null));

    expect(find.text('nas.home.arpa:5055'), findsOneWidget);
    expect(find.byType(QrCodeView), findsOneWidget);
  });

  testWidgets('a server that does not answer leaves the name out, and the '
      'invite is made', (tester) async {
    _mockClipboard(tester);
    await _open(tester, _seerr(), facts: () async => throw StateError('down'));

    expect(find.byType(QrCodeView), findsOneWidget);
    expect(find.text('nas.home.arpa:5055'), findsOneWidget);
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    expect(find.text('Link copied'), findsOneWidget);
    await tester.pump(InviteSheet.copiedFor);
  });

  testWidgets('the code and Copy link are there before the server answers, '
      'and the link is the same after', (tester) async {
    _mockClipboard(tester);
    final answer = Completer<SeerrServerFacts>();
    await _open(tester, _seerr(), facts: () => answer.future);

    // Nothing waits: the code, the host alone, and a button that works.
    expect(find.byType(QrCodeView), findsOneWidget);
    expect(find.text('nas.home.arpa:5055'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed,
      isNotNull,
    );
    final before = _qrData(tester);
    final codeAt = tester.getTopLeft(find.byType(QrCodeView));
    final buttonAt = tester.getTopLeft(find.bySubtype<FilledButton>());
    await tester.tap(find.text('Copy link'));
    await tester.pump(InviteSheet.copiedFor);
    expect(_clipboard, before);

    // A short name, since the test's font is wide: a name and host that wrap
    // under the code would move it by a line.
    answer.complete(_facts(title: 'Rossi'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Rossi · nas.home.arpa:5055'), findsOneWidget);
    expect(_qrData(tester), before, reason: 'the code does not change');
    expect(tester.getTopLeft(find.byType(QrCodeView)), codeAt);
    expect(tester.getTopLeft(find.bySubtype<FilledButton>()), buttonAt);
    _clipboard = null;
    await tester.tap(find.text('Copy link'));
    await tester.pump(InviteSheet.copiedFor);
    expect(_clipboard, before, reason: 'nor does the link');
  });

  testWidgets('Copy link puts exactly the invite\'s link on the clipboard, '
      'says so for two seconds, and is announced', (tester) async {
    _mockClipboard(tester);
    final announcements = SemanticsAnnouncementRecorder.install(tester);
    await _open(tester, _seerr());

    expect(find.text('Copy link'), findsOneWidget);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);

    await tester.tap(find.text('Copy link'));
    await tester.pump();

    final link = SeerrInvite.of(
      _seerr(),
      SettingsModel(instances: [_seerr()]),
    ).toLink();
    expect(_clipboard, link);
    expect(_clipboard, _qrData(tester));
    expect(find.text('Link copied'), findsOneWidget);
    expect(find.text('Copy link'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(announcements.messages, ['Link copied']);

    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Link copied'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Copy link'), findsOneWidget);
    expect(find.text('Link copied'), findsNothing);
    expect(find.byIcon(Icons.link_rounded), findsOneWidget);
  });

  testWidgets('copying again while it says so starts the two seconds over', (
    tester,
  ) async {
    _mockClipboard(tester);
    await _open(tester, _seerr());

    await tester.tap(find.text('Copy link'));
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Link copied'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Link copied'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Copy link'), findsOneWidget);
  });

  testWidgets('closing the sheet while it says Link copied leaves no timer', (
    tester,
  ) async {
    _mockClipboard(tester);
    await _open(tester, _seerr());

    await tester.tap(find.text('Copy link'));
    await tester.pump();
    await tester.tapAt(const Offset(195, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(InviteSheet), findsNothing);
    // The framework fails a test that leaves a timer pending.
  });

  group('what the invite cannot do is said under it, one line each', () {
    Finder lines() => find.byWidgetPredicate(
      (w) =>
          w is Text && const {_homeGate, _homeOnly, _awayGate}.contains(w.data),
    );

    testWidgets('both addresses, none behind a gateway: nothing to say', (
      tester,
    ) async {
      await _open(tester, _seerr());

      expect(lines(), findsNothing);
    });

    testWidgets('no address away: it works at home', (tester) async {
      await _open(tester, _seerr(away: null));

      expect(find.text(_homeOnly), findsOneWidget);
      expect(lines(), findsOneWidget);
      expect(
        Uri.parse(_qrData(tester)).queryParameters,
        isNot(contains('away')),
      );
    });

    testWidgets('the address away behind a gateway is left out, and said', (
      tester,
    ) async {
      await _open(
        tester,
        _seerr(
          away: const ConnectionAddress(
            url: _away,
            access: CloudflareServiceToken(
              clientId: 'sentinel-id',
              clientSecret: 'sentinel-secret',
            ),
          ),
        ),
      );

      expect(find.text(_awayGate), findsOneWidget);
      expect(lines(), findsOneWidget);
      expect(
        Uri.parse(_qrData(tester)).queryParameters,
        isNot(contains('away')),
      );
    });

    testWidgets('the address at home behind a gateway: asked for a token', (
      tester,
    ) async {
      await _open(
        tester,
        _seerr(
          access: const ProxyPassword(
            username: 'sentinel-user',
            password: 'sentinel-password',
          ),
        ),
      );

      expect(find.text(_homeGate), findsOneWidget);
      expect(lines(), findsOneWidget);
    });

    testWidgets('two limits read in the order the domain gives them, above '
        'the button', (tester) async {
      await _open(
        tester,
        _seerr(
          access: const ProxyPassword(
            username: 'sentinel-user',
            password: 'sentinel-password',
          ),
          away: null,
        ),
      );

      expect(lines(), findsNWidgets(2));
      final gate = tester.getTopLeft(find.text(_homeGate)).dy;
      final only = tester.getTopLeft(find.text(_homeOnly)).dy;
      final button = tester.getTopLeft(find.bySubtype<FilledButton>()).dy;
      expect(gate, lessThan(only));
      expect(only, lessThan(button));
    });

    testWidgets('a limit is read plainly, with no tone of its own', (
      tester,
    ) async {
      await _open(tester, _seerr(away: null));

      final colour = tester.widget<Text>(find.text(_homeOnly)).style!.color;
      final scheme = Theme.of(tester.element(find.text(_homeOnly))).colorScheme;
      expect(
        colour,
        CupolaThemeColors.of(tester.element(find.text(_homeOnly))).dimText,
      );
      expect(colour, isNot(scheme.error));
      expect(colour, isNot(scheme.tertiary));
    });
  });

  testWidgets('no secret reaches the QR, the link or the screen', (
    tester,
  ) async {
    _mockClipboard(tester);
    await _open(
      tester,
      _seerr(
        access: const CloudflareServiceToken(
          clientId: 'sentinel-home-id',
          clientSecret: 'sentinel-home-secret',
        ),
        away: const ConnectionAddress(
          url: _away,
          access: ProxyPassword(
            username: 'sentinel-away-user',
            password: 'sentinel-away-password',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Copy link'));
    await tester.pump();

    expect(_clipboard, isNotNull);
    for (final text in [_clipboard!, _qrData(tester)]) {
      expect(text, isNot(contains('sentinel')));
      expect(text, isNot(contains('key')));
      expect(text, isNot(contains('Authorization')));
    }
    expect(find.textContaining('sentinel'), findsNothing);
    await tester.pump(InviteSheet.copiedFor);
  });

  testWidgets('a connection removed while the sheet is open closes it', (
    tester,
  ) async {
    final container = await _open(tester, _seerr());
    expect(find.byType(InviteSheet), findsOneWidget);

    await tester.runAsync(
      () => container
          .read(settingsProvider.notifier)
          .updateSettings(const SettingsModel()),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(InviteSheet), findsNothing);
  });

  testWidgets('a screen reader meets a heading, one image and a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(tester, _seerr());

    expect(
      tester.getSemantics(find.bySemanticsLabel('Invite someone')),
      matchesSemantics(label: 'Invite someone', isHeader: true),
    );
    expect(
      tester.getSemantics(find.byType(QrCodeView)),
      matchesSemantics(label: 'QR code of the invite', isImage: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Copy link')),
      matchesSemantics(
        label: 'Copy link',
        isButton: true,
        isEnabled: true,
        isFocusable: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });
}
