import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_capability.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';

/// The Streaming half of `/activity`'s **Now** bucket.
///
/// `Now` used to hold one record type, and its own comment explained that the
/// single sub-segment existed only because a one-entry bucket renders no pill row
/// at all, while the pills that survived elsewhere had to "express a record type
/// no service filter can reach". An outbound playback is exactly that: downloads
/// are bytes coming in, sessions are bytes going out, and no amount of filtering
/// the arr services reaches one from the other.
///
/// It carries its own type rather than becoming a `GlobalActivityItem`; see
/// [streamActivityProvider] for the 27 exhaustive switches that decision avoids.
class StreamActivitySection extends ConsumerWidget {
  const StreamActivitySection({super.key, required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasStreamServiceProvider)) {
      return _NoStreamService(bottomPadding: bottomPadding);
    }

    final rowsAsync = ref.watch(streamActivityProvider);
    final offline = ref.watch(streamActivityOfflineProvider).value ?? const [];
    final ownerOnly =
        ref.watch(streamActivityOwnerOnlyProvider).value ?? const [];
    final settings = ref.watch(currentSettingsProvider);
    // Above the rows, and above the idle room: the servers that did not
    // answer, in red; the shared Plex accounts, in blue; then each Jellyfin
    // whose token is a household member's, which shows only that member's
    // playback, as its own Now playing says.
    final notes = [
      if (offline.isNotEmpty) _OfflineNote(offline: offline),
      for (final source in ownerOnly) PlexOwnerOnlyNote(server: source.server),
      for (final jellyfin in settings.configuredInstancesOf(
        ServiceKey.jellyfin,
      ))
        if (ref.watch(jellyfinLacksAdministratorForProvider(jellyfin.id)))
          JellyfinOwnPlaybackNote(
            // Named by the app's one rule: only once there is another.
            server: settings.connectionName(jellyfin.id) == null
                ? null
                : settings.connectionTitle(
                    jellyfin.id,
                    ServiceKey.jellyfin,
                    joiner: ' ',
                  ),
            padding: EdgeInsets.zero,
          ),
    ];
    // The servers that could say who is watching: a shared Plex account's
    // cannot.
    final askable = [
      for (final service in ServiceDomain.stream.services)
        for (final instance in settings.configuredInstancesOf(service))
          if (!ownerOnly.any((source) => source.instanceId == instance.id))
            instance,
    ];

    // Every configured server dark. With one connection that is its own leaf:
    // the cause, its address, Settings; with several, the plain-words error
    // state names them together. Counted by connection: two Jellyfin both
    // dark are two servers, not one.
    if (rowsAsync.hasError && !rowsAsync.hasValue) {
      final configured = askable;
      void retry() => _reread(ref);

      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: configured.length == 1
            ? ServiceOfflineState.failure(
                service: configured.single.service,
                error: rowsAsync.error!,
                onRetry: retry,
              )
            : AppErrorState(
                error: rowsAsync.error!,
                serviceName: 'your media servers',
                onRetry: retry,
              ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _reread(ref),
      child: AsyncValueWidget<List<StreamActivityRow>>(
        value: rowsAsync,
        serviceName: 'your media servers',
        onRetry: () {
          ref.invalidate(streamActivityProvider);
          _reread(ref);
        },
        isEmpty: (rows) => rows.isEmpty,
        emptyBuilder: _IdleFeed(
          notes: notes,
          offline: offline.isNotEmpty,
          // Every server a shared Plex account: nobody here could say whether
          // anyone is watching, so the idle room would be a claim nobody made.
          idle: askable.isNotEmpty,
          bottomPadding: bottomPadding,
        ),
        data: (rows) => ListView.separated(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            bottomPadding,
          ),
          itemCount: rows.length + notes.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            // The notes ride at the top of the list rather than above it, so
            // they scroll with the rows instead of pinning a band over content.
            if (index < notes.length) return notes[index];
            final row = rows[index - notes.length];
            return StaggeredEntrance(
              index: index,
              child: StreamSessionCard(
                session: row.session,
                // Each row takes its own server's accent, the way a download row
                // carries its client's: the lamp, for every service, which the
                // row resolves to the room's ink: which server a session is on,
                // the row says in words.
                accent: row.service.accent,
                // Which of two servers it is playing from, once a service has
                // two: `Jellyfin Cabin`. Nothing with one.
                serverName: row.connectionName == null
                    ? null
                    : serviceWithConnection(
                        row.service,
                        row.connectionName,
                        joiner: ' ',
                      ),
                onStop: _stopHandler(context, ref, row),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Asks every media server connection again: the lens's providers, which
  /// the service's own Now playing page shares, and the family the others are
  /// read through.
  static void _reread(WidgetRef ref) {
    ref.invalidate(jellyfinSessionsProvider);
    ref.invalidate(plexSessionsProvider);
    ref.invalidate(streamSessionsForProvider);
  }

  /// The stop control, or null where stopping is not permitted.
  ///
  /// Now playing's gate, [plexStopOfferedProvider], asked of the serving
  /// connection: Plex Pass is per server. It used to re-derive the gate as
  /// `myPlexSubscription != true`, so Stop was missing on every Plex session
  /// until the capability sheet answered, and for good on a build that does
  /// not send the attribute, while Plex's own Now playing drew Stop.
  VoidCallback? _stopHandler(
    BuildContext context,
    WidgetRef ref,
    StreamActivityRow row,
  ) {
    if (row.session.id.isEmpty) return null;
    if (row.service == ServiceKey.plex &&
        !ref.watch(plexStopOfferedProvider(row.instanceId))) {
      return null;
    }
    return () => _confirmStop(context, ref, row);
  }

  Future<void> _confirmStop(
    BuildContext context,
    WidgetRef ref,
    StreamActivityRow row,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Stop playback?',
      message:
          '${streamStopSessionPrompt(userName: row.session.userName, title: row.session.title)} '
          'They can start it again straight away.',
      icon: Icons.stop_circle_outlined,
      confirmLabel: 'Stop playback',
    );
    if (!result.confirmed || !context.mounted) return;

    try {
      // The connection serving the session, never the lens: a session id is
      // that server's, and a stop sent to the other one stops nothing, or
      // someone else.
      final StreamServerClient client = row.service == ServiceKey.jellyfin
          ? ref.read(jellyfinClientForProvider(row.instanceId))
          : ref.read(plexClientForProvider(row.instanceId));
      await client.stopSession(row.session.id);
      // Re-read rather than remove the row: both servers only dispatch a stop,
      // and the client is free to ignore it.
      _reread(ref);
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not stop playback. ${writeFailureReason(row.service, error)}',
        cause: error,
      );
    }
  }
}

/// Nobody watching.
///
/// Reuses the board's own sentence so the two surfaces cannot disagree about the
/// same fact, and states an unreachable source by name when there is one;
/// otherwise a dark server and a quiet house look identical.
///
/// When every server is a Plex whose sessions only its owner sees, the notes
/// say so and the room is not drawn: "nobody is watching" would be a claim
/// about servers that told nobody.
class _IdleFeed extends StatelessWidget {
  const _IdleFeed({
    required this.notes,
    required this.offline,
    required this.idle,
    required this.bottomPadding,
  });

  /// The offline note and the shared-account notes, in that order.
  final List<Widget> notes;

  /// Whether a server did not answer, which takes the room's second line.
  final bool offline;

  /// Whether the idle room is drawn under the notes.
  final bool idle;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        bottomPadding,
      ),
      children: [
        for (final note in notes) ...[
          note,
          const SizedBox(height: AppSpacing.lg),
        ],
        if (idle)
          AppEmptyState(
            icon: Icons.nights_stay_outlined,
            title: streamIdleMessage,
            message: offline
                ? null
                : 'Playback shows up here the moment someone presses play.',
          ),
      ],
    );
  }
}

/// Which media servers could not be read, and why, in the classification's
/// words and tone.
///
/// Keeps its **presence** as the signal and spends the tone on one glyph, per
/// the Quiet Alarm Rule: a home server being down for an afternoon is normal for
/// this product, and alarm chrome for a normal condition trains the user to ignore
/// it.
///
/// Red is for a server that did not answer and nothing else. Those are named
/// together in one red line; every other failure (a refused token, a gateway
/// in front, a certificate) is its own amber line, worded by
/// `failureHeadline`. It used to say "did not answer", in red, for all of
/// them, which sent the user to check a server that had just refused them.
class _OfflineNote extends StatelessWidget {
  const _OfflineNote({required this.offline});

  final List<StreamOfflineSource> offline;

  @override
  Widget build(BuildContext context) {
    final silent = [
      for (final source in offline)
        if (failureDidNotAnswer(classifyConnectionFailure(source.error)))
          source,
    ];
    final faults = [
      for (final source in offline)
        if (!silent.contains(source))
          describeFailureOf(
            source.service,
            source.error,
            subject: source.title,
          ),
    ];

    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (silent.isNotEmpty)
            // By connection, named the way the rows name it: with two
            // Jellyfin, "Jellyfin did not answer" over the other one's
            // sessions says nothing.
            _FailureLine(
              icon: failureIcon(ServiceFailureReason.unreachable),
              tone: failureTone(ServiceFailureReason.unreachable),
              message: servicesAlertBandMessage([
                for (final source in silent) source.title,
              ]),
            ),
          for (final (index, fault) in faults.indexed) ...[
            if (silent.isNotEmpty || index > 0)
              const SizedBox(height: AppSpacing.sm),
            _FailureLine(
              icon: fault.icon,
              tone: fault.tone,
              // A sentence, ended like the red line's.
              message: '${fault.headline}.',
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of [_OfflineNote]: a glyph in the failure's tone, the sentence in
/// the secondary ink.
class _FailureLine extends StatelessWidget {
  const _FailureLine({
    required this.icon,
    required this.tone,
    required this.message,
  });

  final IconData icon;
  final StatusTone tone;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            size: 16,
            // Walked, not raw: the glyph alone carries the tone.
            color: statusToneColor(theme.colorScheme, tone),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// No media server configured yet.
///
/// The sub-segment is still offered, because hiding a record type until it is
/// configured is how a feature becomes undiscoverable, so this names the way in
/// rather than reporting an absence.
class _NoStreamService extends StatelessWidget {
  const _NoStreamService({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.lg,
        bottomPadding,
      ),
      children: [
        AppEmptyState(
          icon: Icons.play_circle_outline_rounded,
          title: 'Jellyfin and Plex are not set up',
          message:
              'Set one up to see who is watching what, and why the box is '
              'working for it.',
          // One `Set up X` per server, each to its own setup form: the
          // Dashboard this used to open left the user to find it.
          action: Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                onPressed: () =>
                    context.go(ServiceRoutes.setUp(ServiceKey.jellyfin)),
                child: Text(Lexicon.setUp(ServiceKey.jellyfin.title)),
              ),
              OutlinedButton(
                onPressed: () =>
                    context.go(ServiceRoutes.setUp(ServiceKey.plex)),
                child: Text(Lexicon.setUp(ServiceKey.plex.title)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
