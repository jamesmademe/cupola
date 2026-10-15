import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What the two pairing screens are tested and drawn with: a sending device
/// worth copying, a link, and notifiers that stand still in a state.

/// A pin that is plainly a fixture.
const pairFixturePin =
    'aa00000000000000000000000000000000000000000000000000000000000001';

/// A sending device: a Radarr and a Sonarr, a Seerr signed in with an
/// account and reached away through Cloudflare, a qBittorrent with a password
/// the keychain would not hand over, and a certificate pinned for its home
/// address.
SettingsModel pairFixtureSender() => const SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'https://radarr.home.arpa',
      credential: 'radarr-fixture-key',
    ),
    ServiceInstance(
      id: 'sonarr',
      service: ServiceKey.sonarr,
      url: 'http://192.168.1.10:8989',
      credential: 'sonarr-fixture-key',
    ),
    ServiceInstance(
      id: 'seerr',
      service: ServiceKey.seerr,
      url: 'http://192.168.1.10:5055',
      account: SeerrAccountSignIn(
        kind: SeerrAccountKind.jellyfin,
        login: 'anna',
        userId: 4,
        displayName: 'Anna',
        session: 'seerr-fixture-session',
        permissions: 32,
      ),
      away: ConnectionAddress(
        url: 'https://seerr.example.net',
        access: CloudflareServiceToken(
          clientId: 'fixture-id',
          clientSecret: 'fixture-secret',
        ),
      ),
    ),
    ServiceInstance(
      id: 'qbittorrent',
      service: ServiceKey.qbittorrent,
      url: 'http://192.168.1.10:8080',
      username: 'admin',
      unreadSecret: UnreadSecret.credential,
    ),
  ],
  trustedCertificates: {'https://radarr.home.arpa:443': pairFixturePin},
);

/// What [pairFixtureSender] hands over, from an iPhone.
PairPackage pairFixturePackage({PairDevice from = PairDevice.iphone}) =>
    PairPackage.everything(pairFixtureSender(), from: from);

/// The 43 characters of [pairFixtureLink]'s key: what no screen may show, log
/// or keep in a location.
const pairFixtureKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

/// A link to a code on a home network, closing at [closesAt]; [invite] for
/// an invite shown in person.
PairLink pairFixtureLink({DateTime? closesAt, bool invite = false}) => PairLink(
  host: InternetAddress('192.168.1.20'),
  port: 47213,
  key: Uint8List.fromList([for (var i = 0; i < PairLink.keyLength; i++) i]),
  closesAt: closesAt ?? DateTime.utc(2030, 1, 1, 12, 2),
  invite: invite,
);

/// An operator's Seerr signed in with the key, reached away through
/// Cloudflare, its away address pinned: what an invite shown in person is
/// made from.
const pairFixtureInviteSeerr = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: 'http://192.168.1.10:5055',
  credential: 'seerr-fixture-key',
  away: ConnectionAddress(
    url: 'https://seerr.example.net',
    access: CloudflareServiceToken(
      clientId: 'fixture-id',
      clientSecret: 'fixture-secret',
    ),
  ),
);

/// The settings [pairFixtureInviteSeerr] lives in.
SettingsModel pairFixtureInviteSender() => const SettingsModel(
  instances: [pairFixtureInviteSeerr],
  trustedCertificates: {'https://seerr.example.net:443': pairFixturePin},
);

/// The invite to [pairFixtureInviteSeerr] shown in person, from an iPhone.
PairPackage pairFixtureInvitePackage() => PairPackage.invite(
  pairFixtureInviteSeerr,
  pairFixtureInviteSender(),
  from: PairDevice.iphone,
);

/// What copying [package] would do over [settings].
PairPlan pairFixturePlan({
  PairPackage? package,
  SettingsModel settings = const SettingsModel(),
}) => PairPlan.of(package ?? pairFixturePackage(), settings);

/// The sending notifier standing in [state]: `start` and `close` only say
/// they were asked.
class FixedPairOffer extends PairOfferNotifier {
  FixedPairOffer(this.fixed);

  final PairOfferState fixed;

  /// The device each `start` was asked to make a code as.
  final started = <PairDevice>[];
  int get starts => started.length;

  /// The connection each `start` was asked to invite to; null for a copy of
  /// everything.
  final invitedTo = <String?>[];
  var closes = 0;

  @override
  PairOfferState build() => fixed;

  /// Moves the screen to [next], as the protocol would.
  void show(PairOfferState next) => state = next;

  /// Whether its provider is still up: false once nothing watches it, which
  /// is what closes a real code's server.
  bool get alive => ref.mounted;

  @override
  Future<void> start({required PairDevice from, String? inviteTo}) async {
    started.add(from);
    invitedTo.add(inviteTo);
  }

  @override
  Future<void> close() async => closes++;
}

/// The receiving notifier standing in [state]: what it is asked is counted.
class FixedPairReceive extends PairReceiveNotifier {
  FixedPairReceive(this.fixed);

  final PairReceiveState fixed;
  var retries = 0;
  var resets = 0;
  var adds = 0;

  @override
  PairReceiveState build() => fixed;

  /// Moves the screen to [next], as the protocol would.
  void show(PairReceiveState next) => state = next;

  @override
  Future<void> retry() async => retries++;

  @override
  void reset() => resets++;

  @override
  Future<void> add() async => adds++;

  @override
  Future<void> receive(PairLink link) async {}

  @override
  void notWhole() {}
}

/// The overrides that hold the sending screen still in [state], and the
/// notifier they made, for a test that counts what it was asked.
typedef FixedOffer = ({Override override, FixedPairOffer notifier});

FixedOffer fixedOffer(PairOfferState state) {
  final notifier = FixedPairOffer(state);
  return (
    override: pairOfferProvider.overrideWith(() => notifier),
    notifier: notifier,
  );
}

typedef FixedReceive = ({Override override, FixedPairReceive notifier});

FixedReceive fixedReceive(PairReceiveState state) {
  final notifier = FixedPairReceive(state);
  return (
    override: pairReceiveProvider.overrideWith(() => notifier),
    notifier: notifier,
  );
}

/// The same, for a scene drawn more than once (a dark sheet and a light one):
/// each container gets a notifier of its own.
Override fixedOfferOf(PairOfferState state) =>
    pairOfferProvider.overrideWith(() => FixedPairOffer(state));

Override fixedReceiveOf(PairReceiveState state) =>
    pairReceiveProvider.overrideWith(() => FixedPairReceive(state));
