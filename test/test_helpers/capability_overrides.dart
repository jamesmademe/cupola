import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';

/// Answers every capability probe from [grants], keyed by connection id.
///
/// A screen of Unraid, TrueNAS or NPM mounts gated controls, and each of them
/// asks `connectionCapabilityProvider` about its connection. Without this the
/// probe reaches the screen's fake client for a method the fake may not
/// implement, fails, and folds to `unanswered`: every write on the page dims
/// and the test passes or fails for a reason it is not about.
///
/// A connection [grants] does not name answers [CapabilityGrant.unknown]:
/// live, the state every write was in before the probe existed.
Override capabilityOverride([Map<String, CapabilityGrant> grants = const {}]) =>
    connectionCapabilityProvider.overrideWith(
      (ref, connectionId) async =>
          grants[connectionId] ?? const CapabilityGrant.unknown(),
    );
