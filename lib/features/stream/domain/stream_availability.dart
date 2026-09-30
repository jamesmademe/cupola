/// Whether an arr's title is on the household's media servers — in the five
/// states the answer can actually be in.
///
/// The slot on a Radarr or Sonarr page used to draw the same nothing for four
/// different facts: no media server set up (the brand book's case a), a server
/// that did not answer (c), a server that answered it does not have the title,
/// and a server whose row for it does not verify (f). Those need four different
/// responses — nothing, one quiet did-not-answer line, `Not on Jellyfin`, and
/// nothing again — and the widget could not tell them apart because the lookup
/// had flattened them into one `null`.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// Where a title sits on a media server, if it is there at all.
typedef StreamMatch = ({ServiceKey service, StreamItem item});

enum StreamAvailabilityState {
  /// A server has the title, and its row verifies as the title.
  found,

  /// No media server is set up here (case a). Decided without asking.
  notSetUp,

  /// A server was asked and did not answer, or answered with a failure — a
  /// refused key included (case c). [StreamAvailability.failure] says which.
  failed,

  /// Every server asked answered, and none has anything under the title's ids.
  /// The one nothing the page may state: `Not on Jellyfin`.
  notInLibrary,

  /// A server has rows for the ids and none verifies as the title (case f), or
  /// the title carries no id to ask by. No link, no Play — and no claim that
  /// the title is missing.
  notVerified,
}

@immutable
class StreamAvailability {
  const StreamAvailability._(
    this.state, {
    this.match,
    this.services = const [],
    this.failure,
  });

  const StreamAvailability.found(StreamMatch match)
    : this._(StreamAvailabilityState.found, match: match);

  const StreamAvailability.notSetUp()
    : this._(StreamAvailabilityState.notSetUp);

  /// [service] failed with [failure].
  StreamAvailability.failed(ServiceKey service, ServiceFailureReason failure)
    : this._(
        StreamAvailabilityState.failed,
        services: [service],
        failure: failure,
      );

  /// Every one of [services] answered "not here".
  const StreamAvailability.notInLibrary(List<ServiceKey> services)
    : this._(StreamAvailabilityState.notInLibrary, services: services);

  const StreamAvailability.notVerified()
    : this._(StreamAvailabilityState.notVerified);

  final StreamAvailabilityState state;

  /// The verified item and its server, on [StreamAvailabilityState.found].
  final StreamMatch? match;

  /// Who the state is about: the server that failed, on
  /// [StreamAvailabilityState.failed]; the servers that answered "not here",
  /// on [StreamAvailabilityState.notInLibrary]. Empty otherwise.
  final List<ServiceKey> services;

  /// Why the lookup failed, on [StreamAvailabilityState.failed].
  final ServiceFailureReason? failure;
}
