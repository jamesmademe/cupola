import 'dart:math';

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/pairing/domain/pair_package.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What copying a [PairPackage] into this device's settings does, worked out
/// before anything is written: what the receiving screen shows, and what
/// Add writes.
///
/// **It adds and never replaces.** A connection this device already has (the
/// same service at one of the same addresses) is [alreadyHere] and left as it
/// is, whatever the package says of it; a pin this device already holds for an
/// origin stays, even when the package's differs. Nothing is removed. A device
/// that copies twice gets nothing the second time.
///
/// The one thing it fills rather than adds to is a connection with no
/// address: what a reinstalled app finds when the keychain kept a key and the
/// address went with the app's preferences. That is no server, and left first
/// it would stay the service's primary with the copied one behind it, so the
/// copy takes its place, under its id.
final class PairPlan {
  const PairPlan._({
    required this.from,
    required this.toAdd,
    required this.alreadyHere,
    required this.certificates,
    required this.orphanCertificates,
    required this.unknown,
    required Map<String, UnreadSecret> sentWithout,
  }) : _sentWithout = sentWithout;

  /// The plan for [package] over [settings]: ids minted against the ones
  /// [settings] uses, a label wherever a service would otherwise hold two
  /// connections without one.
  factory PairPlan.of(
    PairPackage package,
    SettingsModel settings, {
    Random? random,
  }) {
    final taken = {for (final i in settings.instances) i.id};
    final slots = [
      for (final i in settings.instances)
        if (i.url.isEmpty) i,
    ];
    final toAdd = <ServiceInstance>[];
    final alreadyHere = <ServiceInstance>[];
    final sentWithout = <String, UnreadSecret>{};
    for (final incoming in package.connections) {
      if (_sameServer(settings.instances, incoming) ||
          _sameServer(toAdd, incoming)) {
        alreadyHere.add(incoming);
        continue;
      }
      final slot = slots
          .where((s) => s.service == incoming.service)
          .firstOrNull;
      slots.remove(slot);
      final id =
          slot?.id ??
          ServiceInstance.mintId(incoming.service, taken, random: random);
      taken.add(id);
      final siblings = [
        for (final here in settings.instancesOf(incoming.service))
          if (here.url.isNotEmpty) here,
        ...toAdd.where((added) => added.service == incoming.service),
      ];
      toAdd.add(
        ServiceInstance(
          id: id,
          service: incoming.service,
          label: _labelAmong(incoming, siblings),
          url: incoming.url,
          credential: incoming.credential,
          username: incoming.username,
          viewerId: incoming.viewerId,
          access: incoming.access,
          account: incoming.account,
          away: incoming.away,
        ),
      );
      if (incoming.unreadSecret case final missing?) sentWithout[id] = missing;
    }
    return PairPlan._(
      from: package.from,
      toAdd: toAdd,
      alreadyHere: alreadyHere,
      certificates: {
        for (final MapEntry(:key, :value) in package.certificates.entries)
          if ((settings.trustedCertificates[key] ?? '').isEmpty) key: value,
      },
      orphanCertificates: package.orphanCertificates,
      unknown: package.unknown,
      sentWithout: sentWithout,
    );
  }

  /// The device the package came from.
  final PairDevice from;

  /// The connections Add writes, under this device's ids, after the ones it
  /// has (or in the place of one with no address). No secret the sending device could not read is marked here: on this
  /// device nothing failed to read, a secret is simply missing
  /// ([sentWithout]).
  final List<ServiceInstance> toAdd;

  /// The package's connections this device already has, left as they are.
  final List<ServiceInstance> alreadyHere;

  /// The pins Add writes: the package's, for origins this device trusts no
  /// certificate at yet.
  final Map<String, String> certificates;

  /// Certificates the package carried for origins no connection uses, dropped
  /// on reading ([PairPackage.orphanCertificates]).
  final int orphanCertificates;

  /// Connections of a service this build does not know.
  final int unknown;

  final Map<String, UnreadSecret> _sentWithout;

  /// Which secret [connection], one of [toAdd], arrived without because the
  /// sending device could not read it; null when it arrived whole.
  UnreadSecret? sentWithout(ServiceInstance connection) =>
      _sentWithout[connection.id];

  /// The Seerr accounts among [toAdd]: they arrive signed out, and sign in
  /// again here.
  List<ServiceInstance> get signInAgain => [
    for (final connection in toAdd)
      if (connection.account != null) connection,
  ];

  /// Whether Add has anything to write.
  bool get addsAnything => toAdd.isNotEmpty || certificates.isNotEmpty;

  /// [settings], the settings this plan was made over, with [toAdd] after its
  /// connections and [certificates] among its pins.
  SettingsModel applyTo(SettingsModel settings) {
    var next = settings;
    for (final connection in toAdd) {
      next = next.copyWithInstance(connection);
    }
    return next.copyWith(
      trustedCertificates: {...certificates, ...settings.trustedCertificates},
    );
  }

  /// Whether [connections] has one of [incoming]'s service at one of its
  /// addresses.
  static bool _sameServer(
    Iterable<ServiceInstance> connections,
    ServiceInstance incoming,
  ) {
    final addresses = {
      for (final a in incoming.addresses) UrlUtils.normalizeBaseUrl(a),
    };
    return connections.any(
      (here) =>
          here.service == incoming.service &&
          here.addresses.any(
            (a) => addresses.contains(UrlUtils.normalizeBaseUrl(a)),
          ),
    );
  }

  /// [incoming]'s label among [siblings], the connections of its service it
  /// will sit beside: its own when it is alone or its own is free, else one
  /// from its address (`nas`, `192.168.1.20:7878`), numbered when that is
  /// taken too. A second connection of a service never arrives without one.
  static String _labelAmong(
    ServiceInstance incoming,
    List<ServiceInstance> siblings,
  ) {
    if (siblings.isEmpty) return incoming.label;
    final used = {for (final s in siblings) s.label.trim().toLowerCase()};
    final base = incoming.label.trim().isNotEmpty
        ? incoming.label.trim()
        : _labelFromAddress(incoming.url);
    var label = base;
    for (var n = 2; used.contains(label.toLowerCase()); n++) {
      label = '$base $n';
    }
    return label;
  }

  static String _labelFromAddress(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    if (host.isEmpty) return url;
    final isLiteral = RegExp(r'^[0-9.]+$').hasMatch(host) || host.contains(':');
    if (isLiteral) return uri!.hasPort ? '$host:${uri.port}' : host;
    return host.split('.').first;
  }
}
