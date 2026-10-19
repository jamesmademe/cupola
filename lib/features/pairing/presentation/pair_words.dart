import 'package:flutter/material.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/data/pair_session.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The words of copying from another device, in one place: the screen that
/// shows a code and the screen that takes one say each thing the same way.
///
/// None carries a link, a key or a secret: counts, titles of services and
/// the word each service calls its credential.

/// `1 service`, `14 services`.
String pairServices(int count) => count == 1 ? '1 service' : '$count services';

/// `1 trusted certificate`, `3 trusted certificates`.
String pairCertificates(int count) =>
    count == 1 ? '1 trusted certificate' : '$count trusted certificates';

/// `1 service and its key`, `14 services and their keys`.
String pairServicesAndKeys(int count) =>
    count == 1 ? '1 service and its key' : '$count services and their keys';

/// How many titles the sending screen names before `and N more`.
const pairNamedServices = 4;

/// [titles] as a sentence says them: all joined with commas and `and` before
/// the last when there are four or fewer (`Radarr, Sonarr and Seerr`), else
/// the first four and the rest counted (`Radarr, Sonarr, Seerr, Jellyfin and
/// 8 more`).
String pairNamedList(List<String> titles) {
  if (titles.length <= pairNamedServices) {
    return switch (titles) {
      [] => '',
      [final one] => one,
      _ => '${titles.take(titles.length - 1).join(', ')} and ${titles.last}',
    };
  }
  final rest = titles.length - pairNamedServices;
  return '${titles.take(pairNamedServices).join(', ')} and $rest more';
}

/// What a service calls the secret that does not travel: `key`, `token`,
/// `password`: the registry's word for the credential, with a sign-in's
/// secret half named as the password it is.
String pairSecretWord(ServiceKey service) {
  final word = refusedCredentialOf(service);
  return word == kRefusedSignIn ? 'password' : word;
}

/// What one connection left without a secret is called in a sentence:
/// `Radarr`, `Radarr 4K`.
String pairSubject(ServiceInstance connection) =>
    serviceWithConnection(connection.service, connection.label, joiner: ' ');

/// `key`, `password` or `token` for the secret [secret] names of
/// [connection]; `access` for what a gateway in front of it asks for.
String pairSecretNamed(ServiceInstance connection, UnreadSecret secret) =>
    switch (secret) {
      UnreadSecret.credential => pairSecretWord(connection.service),
      UnreadSecret.access => 'access',
    };

/// `Closes in 1:52`: the time left of a code, to the second, never negative.
String pairCountdown(Duration left) {
  final seconds = left.isNegative ? 0 : left.inSeconds;
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return 'Closes in $minutes:$rest';
}

/// One row of what moves with the code: a glyph, what, and what it means.
@immutable
class PairMove {
  const PairMove(this.icon, this.title, this.detail);

  final IconData icon;
  final String title;
  final String detail;
}

/// What [package] hands to the other device, in the order the sending screen
/// says it. Counts and titles only: no address, no key.
List<PairMove> pairMovesOf(PairPackage package) {
  final connections = package.connections;
  return [
    if (connections.isNotEmpty)
      PairMove(
        Icons.key_rounded,
        pairServicesAndKeys(connections.length),
        pairNamedList([
          for (final c in connections)
            serviceWithConnection(c.service, c.label, joiner: ' '),
        ]),
      ),
    if (package.certificates.isNotEmpty)
      PairMove(
        Icons.verified_user_outlined,
        pairCertificates(package.certificates.length),
        'So the new phone trusts the same servers you already trusted',
      ),
    if (connections.any((c) => c.account != null))
      const PairMove(
        Icons.person_outline_rounded,
        'Seerr signs in again on the new phone',
        'A sign-in stays on the device it was made on',
      ),
    for (final c in connections)
      if (c.unreadSecret case final secret?)
        PairMove(
          Icons.key_off_rounded,
          "${pairSubject(c)}'s ${pairSecretNamed(c, secret)} stays behind",
          "This device could not read it. Paste it on the new phone.",
        ),
    const PairMove(
      Icons.wifi_rounded,
      'Encrypted, over your home network only',
      'Both phones need to be on your Wi-Fi',
    ),
  ];
}

/// Why a code closed without sending, as the sending screen says it.
String pairClosedBecause(PairServerEnd how) => switch (how) {
  PairServerEnd.expired => 'Its two minutes are up.',
  PairServerEnd.refused =>
    'Something on your network asked for the wrong thing three times.',
  PairServerEnd.closed || PairServerEnd.sent => "It can't be used any more.",
};

/// A notice the receiving screen draws for a copy that did not arrive: the
/// tone, the headline, the sentence and which verbs remedy it.
@immutable
class PairNotice {
  const PairNotice({
    required this.tone,
    required this.headline,
    required this.sentence,
    required this.fillsStartAgain,
  });

  final StatusTone tone;
  final String headline;
  final String sentence;

  /// Whether `Start again` is the notice's one fill (a fault's remedy, amber)
  /// rather than a ghost beside a line that is red or blue.
  final bool fillsStartAgain;
}

/// What each failure to receive says, and in which tone: red only where the
/// other device did not answer, blue for a code that ran out (the person's
/// own step, never a fault), amber for what arrived wrong.
extension PairReceiveFailureWords on PairReceiveFailure {
  PairNotice get notice => switch (this) {
    PairReceiveFailure.unreachable => const PairNotice(
      tone: StatusTone.error,
      headline: "Cupola could not reach the other device",
      sentence: 'Both need to be on the same Wi-Fi.',
      fillsStartAgain: false,
    ),
    PairReceiveFailure.expired => const PairNotice(
      tone: StatusTone.info,
      headline: 'This code has expired',
      sentence: 'Make a new code on the other device.',
      fillsStartAgain: false,
    ),
    PairReceiveFailure.unreadable => const PairNotice(
      tone: StatusTone.warning,
      headline: "Cupola could not read what the other device sent",
      sentence: 'Make a new code on the other device.',
      fillsStartAgain: true,
    ),
    PairReceiveFailure.newer => const PairNotice(
      tone: StatusTone.warning,
      headline: 'This came from a newer Cupola',
      sentence: 'Update Cupola on this device, then make a new code.',
      fillsStartAgain: true,
    ),
    PairReceiveFailure.notWhole => const PairNotice(
      tone: StatusTone.warning,
      headline: "This link isn't whole",
      sentence: 'Copy it again, or make a new code on the other device.',
      fillsStartAgain: true,
    ),
    PairReceiveFailure.notSaved => const PairNotice(
      tone: StatusTone.warning,
      headline: 'Cupola could not save these services',
      sentence: 'Retry, and restart Cupola if it keeps failing.',
      fillsStartAgain: false,
    ),
  };
}

/// What each failure to open an invite shown in person says: the same
/// tones as a copy's, and the remedy is the person who showed the code,
/// asked for a new one. A link that did not read is not known to be an
/// invite, and says what a copy's does.
extension PairInviteFailureWords on PairReceiveFailure {
  PairNotice get inviteNotice => switch (this) {
    PairReceiveFailure.unreachable => const PairNotice(
      tone: StatusTone.error,
      headline: 'Cupola could not reach the other device',
      sentence: 'Both need to be on the same Wi-Fi.',
      fillsStartAgain: false,
    ),
    PairReceiveFailure.expired => const PairNotice(
      tone: StatusTone.info,
      headline: 'This code has expired',
      sentence: 'Ask for a new one.',
      fillsStartAgain: false,
    ),
    PairReceiveFailure.unreadable => const PairNotice(
      tone: StatusTone.warning,
      headline: 'Cupola could not read the invite',
      sentence: 'Ask for a new code.',
      fillsStartAgain: false,
    ),
    PairReceiveFailure.newer => const PairNotice(
      tone: StatusTone.warning,
      headline: 'This came from a newer Cupola',
      sentence: 'Update Cupola on this device, then ask for a new code.',
      fillsStartAgain: false,
    ),
    PairReceiveFailure.notSaved => const PairNotice(
      tone: StatusTone.warning,
      headline: 'Cupola could not save the invite',
      sentence: 'Ask for a new code, and restart Cupola if it keeps failing.',
      fillsStartAgain: false,
    ),
    PairReceiveFailure.notWhole => notice,
  };
}

/// The label of the primary that writes [plan]: `Add 14 services`, `Add 1
/// service`, or `Add 3 trusted certificates` when only certificates are new.
String pairAddLabel(PairPlan plan) => plan.toAdd.isNotEmpty
    ? 'Add ${pairServices(plan.toAdd.length)}'
    : 'Add ${pairCertificates(plan.certificates.length)}';

/// The dim line of what the copy holds, the counts that are not zero:
/// `14 services · 3 trusted certificates · 2 already here`.
String pairPlanCounts(PairPlan plan) => [
  if (plan.toAdd.isNotEmpty) pairServices(plan.toAdd.length),
  if (plan.certificates.isNotEmpty) pairCertificates(plan.certificates.length),
  if (plan.alreadyHere.isNotEmpty) '${plan.alreadyHere.length} already here',
].join(dotSeparator);

/// The notes under the connections that arrive, only the ones that apply.
List<String> pairPlanNotes(PairPlan plan) => [
  if (plan.signInAgain.isNotEmpty)
    'Sign in to Seerr again here. A sign-in stays on the device it was made '
        'on.',
  for (final c in plan.toAdd)
    if (plan.sentWithout(c) case final secret?)
      '${pairSubject(c)} arrives without its ${pairSecretNamed(c, secret)}. '
          "Paste it here once it's added.",
  if (plan.unknown == 1)
    "1 service this version of Cupola doesn't know stays behind.",
  if (plan.unknown > 1)
    "${plan.unknown} services this version of Cupola doesn't know stay "
        'behind.',
];
