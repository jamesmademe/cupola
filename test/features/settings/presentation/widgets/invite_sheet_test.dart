/// The operator's invite sheet: the QR and the link of one Seerr connection,
/// what the invite cannot do said under it, and nothing secret in either;
/// and, when an address asks for a token, the code shown in person it opens
/// on instead.
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
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/invite_sheet.dart';

import '../../../../test_helpers/pair_fixtures.dart';
import '../../../../test_helpers/semantics_announcements.dart';
import '../../../../test_helpers/settings_scope.dart';

const _id = 'seerr';
const _home = 'https://nas.home.arpa:5055';
const _away = 'https://seerr.example.net';

const _homeGate =
    'The address at home asks for a token, and a link never carries one.';
const _homeOnly = 'It works at home: Seerr has no address away from home.';
const _awayGate =
    'It works at home: the address away asks for a token, and a link never '
    'carries one.';

const _inPerson =
    'On your Wi-Fi, they scan this with their phone\'s camera and sign in to '
    'Seerr with their own account.';

const _awayToken = ConnectionAddress(
  url: _away,
  access: CloudflareServiceToken(
    clientId: 'sentinel-id',
    clientSecret: 'sentinel-secret',
  ),
);

const _homeToken = ProxyPassword(
  username: 'sentinel-user',
  password: 'sentinel-password',
);

/// The code shown in person, up.
PairOfferState _up() => PairOfferOpen(
  link: pairFixtureLink(invite: true),
  package: pairFixtureInvitePackage(),
);

/// The notifiers the sheet's code was made with, in order: one each time the
/// sheet turned to the code.
final _offers = <FixedPairOffer>[];

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
///
/// The code shown in person stands in [offer] (up, by default): the protocol
/// itself is tested on loopback in `pair_session_test`.
Future<ProviderContainer> _open(
  WidgetTester tester,
  ServiceInstance connection, {
  Future<SeerrServerFacts> Function()? facts,
  PairOfferState Function()? offer,
}) async {
  final overrides = await settingsScopeOverrides(
    customize: (_) => SettingsModel(instances: [connection]),
  );
  _offers.clear();
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
        inviteOfferProvider.overrideWith(() {
          final fixed = FixedPairOffer((offer ?? _up)());
          _offers.add(fixed);
          return fixed;
        }),
        pairNetworkProvider.overrideWithValue(
          PairNetwork(now: () => DateTime.utc(2030, 1, 1, 12)),
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

/// Turns the sheet to the link.
Future<void> _toLink(WidgetTester tester) async {
  await tester.tap(find.text('Send a link instead'));
  await tester.pump();
}

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
    expect(find.text('Rossi Movies\u00A0· nas.home.arpa:5055'), findsOneWidget);
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

    expect(find.text('Rossi\u00A0· nas.home.arpa:5055'), findsOneWidget);
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

    testWidgets('on the link, the address away behind a gateway is left out, '
        'and said', (tester) async {
      await _open(tester, _seerr(away: _awayToken));
      await _toLink(tester);

      expect(find.text(_awayGate), findsOneWidget);
      expect(lines(), findsOneWidget);
      expect(
        Uri.parse(_qrData(tester)).queryParameters,
        isNot(contains('away')),
      );
    });

    testWidgets('on the link, the address at home behind a gateway: asked '
        'for a token', (tester) async {
      await _open(tester, _seerr(access: _homeToken));
      await _toLink(tester);

      expect(find.text(_homeGate), findsOneWidget);
      expect(lines(), findsOneWidget);
    });

    testWidgets('two limits read in the order the domain gives them, above '
        'the button', (tester) async {
      await _open(tester, _seerr(access: _homeToken, away: null));
      await _toLink(tester);

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
    await _toLink(tester);
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

  group('with a token a link never carries, the code shown in person', () {
    testWidgets('the sheet opens on it: a code for this Seerr, the server\'s '
        'name, the time left, and what it brings', (tester) async {
      await _open(tester, _seerr(away: _awayToken));

      expect(find.text(_inPerson), findsOneWidget);
      expect(_offers.single.invitedTo, [_id]);
      final code = Uri.parse(_qrData(tester));
      expect(code.host, 'pair');
      expect(code.queryParameters['t'], 'invite');
      expect(tester.getSize(find.byType(QrCodeView)), const Size.square(232));
      expect(
        find.text('Rossi Movies\u00A0· nas.home.arpa:5055'),
        findsOneWidget,
      );
      expect(find.text('Closes in 2:00'), findsOneWidget);
      expect(
        find.text(
          "It brings the token the address away asks for. Seerr's key stays "
          'here.',
        ),
        findsOneWidget,
      );
      expect(find.text('Send a link instead'), findsOneWidget);
      expect(
        find.text('A link works only at home: it never carries a token.'),
        findsOneWidget,
      );
      // No second link beside the one it offers instead.
      expect(find.text('Copy link'), findsNothing);
    });

    testWidgets('what it brings names the address that asks', (tester) async {
      await _open(tester, _seerr(access: _homeToken, away: null));

      expect(
        find.text(
          "It brings the token the address at home asks for. Seerr's key "
          'stays here.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('A link never carries a token: they would be asked for it.'),
        findsOneWidget,
      );
    });

    testWidgets('both addresses asking, it brings both', (tester) async {
      await _open(tester, _seerr(access: _homeToken, away: _awayToken));

      expect(
        find.text(
          "It brings the tokens both addresses ask for. Seerr's key stays "
          'here.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Send a link instead turns to the link and lets the code go; '
        'Invite in person instead makes a new one', (tester) async {
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      await _open(tester, _seerr(away: _awayToken));
      final first = _offers.single;

      await _toLink(tester);
      expect(find.text(_inPerson), findsNothing);
      expect(Uri.parse(_qrData(tester)).host, 'invite');
      expect(find.text('Copy link'), findsOneWidget);
      expect(find.text('Invite in person instead'), findsOneWidget);
      // Nothing watches the code now: its provider goes, and the server with
      // it.
      await tester.pump();
      expect(first.alive, isFalse);

      await tester.tap(find.text('Invite in person instead'));
      await tester.pump();
      await tester.pump();
      expect(find.text(_inPerson), findsOneWidget);
      expect(_offers, hasLength(2));
      expect(_offers.last.invitedTo, [_id]);
      expect(announcements.messages, [
        'The invite is a link',
        'The invite is a code to scan here',
      ]);
    });

    testWidgets('with no token to bring, there is no code in person', (
      tester,
    ) async {
      await _open(tester, _seerr());

      expect(find.text(_inPerson), findsNothing);
      expect(find.text('Invite in person instead'), findsNothing);
      expect(find.text('Send a link instead'), findsNothing);
      expect(_offers, isEmpty);
    });

    testWidgets('taken by their phone: said, and Done closes the sheet', (
      tester,
    ) async {
      await _open(
        tester,
        _seerr(away: _awayToken),
        offer: () => PairOfferSent(pairFixtureInvitePackage()),
      );

      expect(find.text('They have the invite'), findsOneWidget);
      expect(
        find.text(
          'They sign in to Seerr on their phone now. The code is '
          'closed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Send a link instead'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(InviteSheet), findsNothing);
    });

    testWidgets('closed: why, and Make a new code', (tester) async {
      await _open(
        tester,
        _seerr(away: _awayToken),
        offer: () => const PairOfferClosed(PairServerEnd.expired),
      );

      expect(find.text('The code closed'), findsOneWidget);
      expect(find.text('Its two minutes are up.'), findsOneWidget);
      await tester.tap(find.text('Make a new code'));
      await tester.pump();
      expect(_offers.single.invitedTo, [_id, _id]);
    });

    testWidgets('off the Wi-Fi: blue, with Retry, the link still a tap away', (
      tester,
    ) async {
      await _open(
        tester,
        _seerr(away: _awayToken),
        offer: () => const PairOfferNoNetwork(),
      );

      expect(find.text('Join your Wi-Fi to invite in person'), findsOneWidget);
      expect(
        find.text('Their phone fetches the invite over your home network.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(_offers.single.invitedTo, [_id, _id]);
      expect(find.text('Send a link instead'), findsOneWidget);
    });

    testWidgets('the code would not open: amber, and Make a new code', (
      tester,
    ) async {
      await _open(
        tester,
        _seerr(away: _awayToken),
        offer: () => const PairOfferFailed(),
      );

      expect(find.text('Cupola could not open the code'), findsOneWidget);
      expect(find.text('Make a new code'), findsOneWidget);
    });

    testWidgets('no secret reaches the screen', (tester) async {
      await _open(tester, _seerr(access: _homeToken, away: _awayToken));

      expect(find.textContaining('sentinel'), findsNothing);
      expect(_qrData(tester), isNot(contains('sentinel')));
    });
  });
}
