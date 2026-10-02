import 'package:flutter/foundation.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The fixed sentences one gated surface speaks, in one place per feature.
///
/// Every capability surface says the same few things — the banner, the hint on
/// a dimmed control, the toast when a write is refused — and they must agree
/// with each other and with the service's own vocabulary. Written inline at
/// forty call sites they would not. A feature declares one value per resource
/// it gates (`unraid_capability.dart`, `truenas_capability.dart`,
/// `npm_capability.dart`) and every surface reads from it.
///
/// Voice: sentence case, two sentences for a banner — what this credential can
/// do, then what it cannot — naming the service and the credential in the
/// service's own terms. A banner that lists only refusals reads as breakage.
@immutable
class CapabilityCopy {
  const CapabilityCopy({
    required this.service,
    required this.answered,
    required this.scope,
    required this.hint,
    String? refusal,
    this.partial,
  }) : _refusal = refusal;

  final ServiceKey service;

  /// The banner when the service said this credential may not write here:
  /// *"This Unraid key can read. Starting and stopping VMs needs a key with
  /// write access to VMs."*
  final String answered;

  /// What the missing permission is, as the tail of a sentence: `write access
  /// to VMs`, `an admin account`. Spliced into the refusal sentences so they
  /// name the fix rather than the failure.
  final String scope;

  /// The `requires …` fragment a dimmed control carries: `requires a key that
  /// can write VMs`. A hint, not part of the name, so a reader can still say
  /// the name alone.
  final String hint;

  /// The banner for a credential that may write *some* of what the page
  /// offers, given the page's resources it may not write. Null means [answered]
  /// is already right for that case — a page that gates one resource.
  final String Function(Set<String> restricted)? partial;

  final String? _refusal;

  String get _noun => service.capabilityCredentialNoun;

  /// The toast a refused write raises, the one that also marks the connection.
  String get refusal =>
      _refusal ??
      '${service.title} refused this with the saved $_noun. It can still '
          'read; this needs $scope.';

  /// The banner after a refusal in this session.
  String get refused =>
      '${service.title} refused a change from this $_noun. It can still '
      'read; changes need $scope.';

  /// The banner when Cupola could not ask. Not a claim about the credential,
  /// which may well be fine — which is why its action is *Check again* and
  /// not a new key.
  String get unanswered => CapabilityCopy.unansweredBanner(service);

  /// The banner for [grant] on a page whose restricted resources are
  /// [restricted].
  String bannerFor(CapabilityGrant grant, Set<String> restricted) =>
      switch (grant.basis) {
        CapabilityBasis.unanswered => unanswered,
        CapabilityBasis.refused => refused,
        CapabilityBasis.answered =>
          grant.writable != null && partial != null
              ? partial!(restricted)
              : answered,
      };

  /// The unanswered banner, for any scoped service.
  static String unansweredBanner(ServiceKey service) =>
      'Cupola could not check what this ${service.title} '
      '${service.capabilityCredentialNoun} may change, so changes are held '
      'back until it can. Reads are unaffected.';

  /// The hint a dimmed control carries while the probe could not ask.
  static String unansweredHint(ServiceKey service) =>
      'this ${service.capabilityCredentialNoun}\'s permissions are unknown';

  /// The toast a dimmed control raises while the probe could not ask.
  static String unansweredToast(ServiceKey service) =>
      'Cupola could not check this ${service.capabilityCredentialNoun}\'s '
      'permissions, so it\'s holding changes back.';
}

/// Which connection a write belongs to, and what to say if it is refused.
///
/// Handed to the action runners so a permission refusal marks **that**
/// connection read-only and raises a toast whose one action lands on **that**
/// connection's settings form.
@immutable
class CapabilityTarget {
  const CapabilityTarget({required this.connectionId, required this.copy});

  final String connectionId;
  final CapabilityCopy copy;

  ServiceKey get service => copy.service;
}
