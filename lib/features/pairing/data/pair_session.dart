import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/discover/domain/seerr_invite.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/pairing/data/pair_fetch.dart';
import 'package:cupola/features/pairing/data/pair_server.dart';
import 'package:cupola/features/pairing/domain/pair_cipher.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/pairing/domain/pair_plan.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

/// What pairing reaches the network through: where this device's server
/// stands, how long a code lives, how a package is fetched, and the clock.
/// One provider so a test swaps all of it at once.
@immutable
class PairNetwork {
  const PairNetwork({
    this.lifetime = const Duration(minutes: 2),
    this.findAddress = pairingAddress,
    this.fetch = fetchPairPackage,
    this.now = DateTime.now,
  });

  final Duration lifetime;
  final Future<InternetAddress?> Function() findAddress;
  final Future<PairPackage> Function(PairLink link) fetch;
  final DateTime Function() now;
}

final pairNetworkProvider = Provider<PairNetwork>((_) => const PairNetwork());

// ── The link on its way in ──────────────────────────────────────────────────

/// A pairing link the router took off the location: the link, or null for
/// one that did not read ([PairLink.fromQuery]).
@immutable
final class PairArrival {
  const PairArrival(this.link);

  final PairLink? link;

  @override
  String toString() => 'PairArrival(${link ?? 'not whole'})';
}

/// Holds the pairing link between the router, which takes it off the
/// location the moment it arrives, and the receiving screen, which takes it
/// from here. Nothing else ever holds the key: not the location, not a route's
/// history, not a log.
class PendingPairNotifier extends Notifier<PairArrival?> {
  @override
  PairArrival? build() => null;

  /// What the router calls with a link off the location.
  void hold(PairArrival arrival) => state = arrival;

  /// The arrival held, gone from here once taken.
  PairArrival? take() {
    final arrival = state;
    state = null;
    return arrival;
  }
}

final pendingPairProvider = NotifierProvider<PendingPairNotifier, PairArrival?>(
  PendingPairNotifier.new,
);

/// Holds an invite shown in person between the receiving screen, which
/// opened it, and the sign-in it hands over to. It carries what a gateway
/// asks for, so it never travels in a location: the sign-in takes it from
/// here, once.
class PendingInviteNotifier extends Notifier<SeerrInvite?> {
  @override
  SeerrInvite? build() => null;

  void hold(SeerrInvite invite) => state = invite;

  /// The invite held, gone from here once taken.
  SeerrInvite? take() {
    final invite = state;
    state = null;
    return invite;
  }
}

final pendingInviteProvider =
    NotifierProvider<PendingInviteNotifier, SeerrInvite?>(
      PendingInviteNotifier.new,
    );

// ── The device that sends ───────────────────────────────────────────────────

/// Where the sending screen stands.
sealed class PairOfferState {
  const PairOfferState();
}

/// Sealing the package and opening the server.
final class PairOfferPreparing extends PairOfferState {
  const PairOfferPreparing();
}

/// The code is up: [link] is what it holds, [package] what it hands over.
final class PairOfferOpen extends PairOfferState {
  const PairOfferOpen({required this.link, required this.package});

  final PairLink link;
  final PairPackage package;
}

/// The other device took the package, whole.
final class PairOfferSent extends PairOfferState {
  const PairOfferSent(this.package);

  final PairPackage package;
}

/// The code closed without sending: [how] says why.
final class PairOfferClosed extends PairOfferState {
  const PairOfferClosed(this.how);

  final PairServerEnd how;
}

/// This device is on no home network: no code can be made.
final class PairOfferNoNetwork extends PairOfferState {
  const PairOfferNoNetwork();
}

/// The server could not be opened (a sandbox without the right, a port the
/// system refused).
final class PairOfferFailed extends PairOfferState {
  const PairOfferFailed();
}

/// The sending side: seals everything this device has, opens the server, and
/// closes it when the screen goes, whatever state it is in.
class PairOfferNotifier extends Notifier<PairOfferState> {
  PairServer? _server;
  var _generation = 0;

  @override
  PairOfferState build() {
    ref.onDispose(() {
      _generation++;
      _server?.close();
      _server = null;
    });
    return const PairOfferPreparing();
  }

  /// Makes a code for everything this device has, as [from]; with
  /// [inviteTo], the id of a Seerr connection, an invite to that Seerr shown
  /// in person instead ([PairPackage.invite]). Closes the one up before, if
  /// any.
  Future<void> start({required PairDevice from, String? inviteTo}) async {
    final generation = ++_generation;
    await _server?.close();
    _server = null;
    state = const PairOfferPreparing();

    final network = ref.read(pairNetworkProvider);
    final settings = ref.read(currentSettingsProvider);
    final seerr = inviteTo == null ? null : settings.instanceById(inviteTo);
    if (inviteTo != null && seerr == null) {
      state = const PairOfferFailed();
      return;
    }
    final package = seerr == null
        ? PairPackage.everything(settings, from: from)
        : PairPackage.invite(seerr, settings, from: from);
    final address = await network.findAddress();
    if (generation != _generation) return;
    if (address == null) {
      state = const PairOfferNoNetwork();
      return;
    }
    final key = PairCipher.newKey();
    final PairServer server;
    try {
      final sealed = await PairCipher.seal(key, package.encode());
      server = await PairServer.open(
        address: address,
        key: key,
        sealed: sealed,
        invite: package.invite,
        lifetime: network.lifetime,
        now: network.now,
      );
    } on Object {
      if (generation == _generation) state = const PairOfferFailed();
      return;
    }
    if (generation != _generation) {
      await server.close();
      return;
    }
    _server = server;
    server.ended.addListener(() {
      if (generation != _generation) return;
      final how = server.ended.value;
      if (how == null) return;
      state = how == PairServerEnd.sent
          ? PairOfferSent(package)
          : PairOfferClosed(how);
    });
    state = PairOfferOpen(link: server.link, package: package);
  }

  /// Closes the code now.
  Future<void> close() async => _server?.close();
}

final pairOfferProvider =
    NotifierProvider.autoDispose<PairOfferNotifier, PairOfferState>(
      PairOfferNotifier.new,
    );

/// The invite sheet's own code, apart from Set up another device's: the same
/// notifier, closed with the sheet, or as soon as the sheet turns to the link.
final inviteOfferProvider =
    NotifierProvider.autoDispose<PairOfferNotifier, PairOfferState>(
      PairOfferNotifier.new,
    );

// ── The device that receives ────────────────────────────────────────────────

/// Why nothing arrived, as the receiving screen says it.
enum PairReceiveFailure {
  /// The link was cut or changed on the way.
  notWhole,

  /// Nothing answered at the other device's address.
  unreachable,

  /// The code's two minutes are over.
  expired,

  /// What arrived did not open.
  unreadable,

  /// A later Cupola sent it.
  newer;

  static PairReceiveFailure of(PairFetchFailure failure) => switch (failure) {
    PairFetchFailure.unreachable => unreachable,
    PairFetchFailure.expired => expired,
    PairFetchFailure.unreadable => unreadable,
    PairFetchFailure.newer => newer,
  };
}

/// Where the receiving screen stands.
sealed class PairReceiveState {
  const PairReceiveState();
}

/// No link yet: the screen says how to get one.
final class PairReceiveWaiting extends PairReceiveState {
  const PairReceiveWaiting();
}

/// Fetching from the other device; [invite] when the link said it is an
/// invite shown in person.
final class PairReceiveFetching extends PairReceiveState {
  const PairReceiveFetching({this.invite = false});

  final bool invite;
}

/// The package arrived: [plan] is what Add would do.
final class PairReceivePreview extends PairReceiveState {
  const PairReceivePreview(this.plan);

  final PairPlan plan;
}

/// Nothing arrived, for [failure]; [invite] when the link said it is an
/// invite shown in person.
final class PairReceiveFailed extends PairReceiveState {
  const PairReceiveFailed(this.failure, {this.invite = false});

  final PairReceiveFailure failure;

  final bool invite;

  /// Whether fetching again can still succeed: the same code, while it is
  /// open, from a device that did not answer.
  bool get retryHelps => failure == PairReceiveFailure.unreachable;
}

/// Writing [plan].
final class PairReceiveAdding extends PairReceiveState {
  const PairReceiveAdding(this.plan);

  final PairPlan plan;
}

/// An invite shown in person arrived. With no Seerr here at its addresses
/// ([here] null) it waits in [pendingInviteProvider] for the sign-in; with
/// one, [here] is that connection with what it lacked filled in ([updated]
/// when anything was).
final class PairReceiveInvited extends PairReceiveState {
  const PairReceiveInvited({this.here, this.updated = false});

  final ServiceInstance? here;
  final bool updated;
}

/// [plan] is written: the connections are this device's now.
final class PairReceiveAdded extends PairReceiveState {
  const PairReceiveAdded(this.plan);

  final PairPlan plan;
}

/// The receiving side: takes a link from [pendingPairProvider] (or a pasted
/// one), fetches and opens the package, shows what it would add, and adds it.
///
/// Holds the link only while it can still be used: dropped once the package
/// arrived, and with the screen.
class PairReceiveNotifier extends Notifier<PairReceiveState> {
  PairLink? _link;
  PairPackage? _package;
  var _generation = 0;

  @override
  PairReceiveState build() {
    ref.onDispose(() {
      _generation++;
      _link = null;
      _package = null;
    });
    ref.listen(pendingPairProvider, (_, next) {
      if (next != null) _takePending();
    });
    if (ref.read(pendingPairProvider) != null) {
      Future.microtask(_takePending);
    }
    return const PairReceiveWaiting();
  }

  void _takePending() {
    final arrival = ref.read(pendingPairProvider.notifier).take();
    if (arrival == null) return;
    final link = arrival.link;
    if (link == null) {
      _generation++;
      _link = null;
      state = const PairReceiveFailed(PairReceiveFailure.notWhole);
    } else {
      receive(link);
    }
  }

  /// Fetches what [link] names: from the code, or pasted.
  Future<void> receive(PairLink link) async {
    final generation = ++_generation;
    _link = link;
    _package = null;
    state = PairReceiveFetching(invite: link.invite);
    try {
      final package = await ref.read(pairNetworkProvider).fetch(link);
      if (generation != _generation) return;
      _link = null;
      // The link's mark is only a word; the sealed package is what was sent.
      // The two disagree only when something is wrong with one of them.
      if (package.invite != link.invite) {
        state = PairReceiveFailed(
          PairReceiveFailure.unreadable,
          invite: link.invite,
        );
        return;
      }
      if (package.asInvite() case final invite?) {
        await _invited(invite, generation);
        return;
      }
      _package = package;
      state = PairReceivePreview(
        PairPlan.of(package, ref.read(currentSettingsProvider)),
      );
    } on PairFetchException catch (e) {
      if (generation != _generation) return;
      state = PairReceiveFailed(
        PairReceiveFailure.of(e.failure),
        invite: link.invite,
      );
    }
  }

  /// An invite shown in person: held for the sign-in when no Seerr here is
  /// at its addresses, else written into the one that is, only where it
  /// lacks something ([SeerrInvite.fill]), with the pins of its addresses
  /// this device does not keep yet.
  Future<void> _invited(SeerrInvite invite, int generation) async {
    final settings = ref.read(currentSettingsProvider);
    final here = invite.connectedIn(settings);
    if (here == null) {
      ref.read(pendingInviteProvider.notifier).hold(invite);
      state = const PairReceiveInvited();
      return;
    }
    final filled = invite.fill(here);
    var next = identical(filled, here)
        ? settings
        : settings.copyWithInstance(filled);
    for (final address in filled.addresses) {
      final pin = invite.pinFor(address);
      if (pin != null && next.pinForUrl(address) == null) {
        next = next.copyWithTrustedCertificate(url: address, fingerprint: pin);
      }
    }
    final updated = !identical(next, settings);
    if (updated) {
      await ref.read(settingsProvider.notifier).updateSettings(next);
      if (!ref.mounted || generation != _generation) return;
    }
    state = PairReceiveInvited(here: filled, updated: updated);
  }

  /// A pasted link that did not read.
  void notWhole() {
    _generation++;
    _link = null;
    state = const PairReceiveFailed(PairReceiveFailure.notWhole);
  }

  /// Fetches the same link again, while it is held.
  Future<void> retry() async {
    final link = _link;
    if (link != null) await receive(link);
  }

  /// Back to waiting for a link, forgetting the one held.
  void reset() {
    _generation++;
    _link = null;
    _package = null;
    state = const PairReceiveWaiting();
  }

  /// Adds what arrived, over the settings as they are now, and ends the way
  /// in: the device has connections.
  Future<void> add() async {
    final package = _package;
    if (package == null || state is! PairReceivePreview) return;
    final current = ref.read(currentSettingsProvider);
    final plan = PairPlan.of(package, current);
    state = PairReceiveAdding(plan);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(plan.applyTo(current));
    await ref.read(settingsServiceProvider).saveOnboardingComplete();
    ref.read(onboardingCompletedProvider.notifier).state = true;
    _package = null;
    state = PairReceiveAdded(plan);
  }
}

final pairReceiveProvider =
    NotifierProvider.autoDispose<PairReceiveNotifier, PairReceiveState>(
      PairReceiveNotifier.new,
    );
