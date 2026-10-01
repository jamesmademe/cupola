/// What a Plex token may do, and the sentence a shared account's token earns.
///
/// A Plex token is a person's, not a server's. The owner's reads everything
/// the server has, including who is watching. A token of an account the owner
/// shared the server with (a friend, a managed or home user) reads the
/// libraries it was given and is refused `/status/sessions` with a 401, the
/// same status a wrong token gets everywhere. Without asking, Now playing
/// reported that 401 as a refused credential, and the user went off to
/// replace a token that was working exactly as it was issued: case d, not a
/// fault.
///
/// Plex has no endpoint that says whose a token is, so the probe asks the two
/// routes that tell the cases apart: `/status/sessions` (the owner's) and `/`
/// (any token the server accepts).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';

/// The resource a shared account's token may not reach: who is watching, and
/// stopping it.
const plexSessionsResource = 'sessions';

/// Asks the Plex saved for [connectionId] whose token it holds.
///
/// `/status/sessions` answering is the owner's token: read-write. Refused
/// there while `/` still answers is a shared account's token:
/// `partial({})`, the server reads and its sessions do not. Refused on both
/// is a token Plex does not accept at all, which is the connection's own
/// failure to report and not a scope, so it is `unanswered`, like a probe
/// that could not ask.
///
/// Watches the connection's client, so a new token re-asks.
Future<CapabilityGrant> probePlexCapability(
  Ref ref,
  String connectionId,
) async {
  try {
    final client = ref.watch(plexClientForProvider(connectionId));
    try {
      await client.getSessionsOrThrow();
      return const CapabilityGrant.readWrite();
    } on PlexException catch (error) {
      if (error.tokenIssue != PlexTokenIssue.rejected) {
        return const CapabilityGrant.unanswered();
      }
    }
    // `verifyCredential` is `GET /`, false only for a refusal: a transport
    // failure rethrows into the catch below.
    return await client.verifyCredential()
        ? const CapabilityGrant.partial({})
        : const CapabilityGrant.unanswered();
  } catch (_) {
    return const CapabilityGrant.unanswered();
  }
}

/// Whether [grant] is a shared account's token: the server answered the
/// probe, and the token may not reach the sessions.
bool plexIsSharedAccount(CapabilityGrant grant) =>
    grant.basis == CapabilityBasis.answered &&
    grant.scopeFor(plexSessionsResource).isRestricted;

/// What a failed sessions read on a Plex connection turned out to be.
enum PlexSessionsRefusal {
  /// A failure like any other: the classification says what it was.
  failure,

  /// Refused, and the probe has not said whose the token is yet.
  pending,

  /// Refused because only the owner's token sees the sessions.
  ownerOnly,
}

/// Reads what a failed sessions read of [connectionId] means, for a widget.
///
/// Only a refusal asks the probe: a server that did not answer, or answered
/// something that is not Plex, keeps its own classification.
PlexSessionsRefusal plexSessionsRefusal(
  WidgetRef ref,
  String connectionId,
  Object? error,
) {
  if (classifyConnectionFailure(error) != ServiceFailureReason.unauthorized) {
    return PlexSessionsRefusal.failure;
  }
  return ref
      .watch(connectionCapabilityProvider(connectionId))
      .when(
        data: (grant) => plexIsSharedAccount(grant)
            ? PlexSessionsRefusal.ownerOnly
            : PlexSessionsRefusal.failure,
        loading: () => PlexSessionsRefusal.pending,
        error: (_, _) => PlexSessionsRefusal.failure,
      );
}

/// The same question from a provider: whether a failed sessions read is a
/// shared account's, asked of [probe] (the connection's
/// `connectionCapabilityProvider`) only when the read was refused.
///
/// The probe is handed in rather than read here because the caller may be
/// past an `await` by now, where an `autoDispose` provider's `ref` must not be
/// used: it passes a reader it captured before the gap.
Future<bool> plexSessionsOwnerOnly(
  Future<CapabilityGrant> Function() probe,
  Object? error,
) async {
  if (classifyConnectionFailure(error) != ServiceFailureReason.unauthorized) {
    return false;
  }
  try {
    return plexIsSharedAccount(await probe());
  } catch (_) {
    return false;
  }
}

/// The sentence a shared account's Plex earns where Now playing would be.
///
/// [server] names the connection when the household has two Plex servers;
/// null is "this Plex server", on that server's own pages and wherever it is
/// the only one.
String plexOwnerOnlyMessage({String? server}) =>
    'Only the owner of ${server ?? 'this Plex server'} sees what\'s playing.';

/// Now playing, on a Plex token that may not see it.
///
/// Blue: the token is doing what it was issued to do, and nothing is broken.
/// One glyph carries the tone and the sentence is `onSurfaceVariant`, the line
/// the idle room and the capability banner are drawn in. No action: a shared
/// account cannot become the owner from here, and the owner's token is not
/// something Cupola can ask the user for as if they had it.
class PlexOwnerOnlyNote extends StatelessWidget {
  const PlexOwnerOnlyNote({super.key, this.server});

  /// The connection's name when there are two Plex servers.
  final String? server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.person_outline_rounded,
              size: 16,
              color: statusToneColor(
                colorScheme,
                StatusTone.info,
                surface: colorScheme.surface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              plexOwnerOnlyMessage(server: server),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
