import 'package:flutter/material.dart';

import 'package:cupola/core/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_copy.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/request_form_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The sheet a request is sent from, on a title's page.
///
/// Two sheets, as the gate of the lens's Seerr says. The operator whose
/// connection may choose picks the server, the quality profile and the
/// folder, as he always has. Everybody else (the requester, and an operator's
/// account on somebody else's Seerr) sends the title alone: its quality,
/// standard or 4K where the account and the server both take 4K, its seasons
/// where the server takes them one by one, under a line that says who
/// approves it and how much of the quota is left. The server applies its own
/// server, profile and folder, and no name of the operator's servers is read.
class RequestBottomSheet extends ConsumerWidget {
  final int mediaId;
  final String mediaType;

  /// What the request is for, named in the requester's words when it fails.
  final String? title;

  /// The copies a request may be for, from the request gate. Every server is
  /// offered when both are.
  final SeerrRequestCopies copies;
  final VoidCallback onRequestComplete;

  /// The other way to add the title, offered quietly at the foot: the arr
  /// it can be added to straight away. Null when there is none.
  final ({String label, VoidCallback onTap})? alternative;

  const RequestBottomSheet({
    super.key,
    required this.mediaId,
    required this.mediaType,
    this.copies = SeerrRequestCopies.both,
    required this.onRequestComplete,
    this.title,
    this.alternative,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (mediaId: mediaId, mediaType: mediaType, copies: copies);
    final state = ref.watch(requestFormProvider(args));
    final notifier = ref.read(requestFormProvider(args).notifier);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final gate = ref.watch(roleGateProvider(''));
    final kind = mediaType == 'movie'
        ? SeerrMediaKind.movie
        : SeerrMediaKind.tv;

    // Without the pickers: what the server says this account may still ask
    // for, read each time the sheet opens. The key has no quota to read.
    final lensId = ref.watch(activeInstanceProvider(ServiceKey.seerr))?.id;
    final quota = state.choosesDestination || lensId == null
        ? null
        : ref.watch(seerrQuotaProvider(lensId)).value;
    final submitVerdict = state.choosesDestination
        ? const Live()
        : gate.requestAction(kind, quota: quota);
    // Whether the server takes a series one season at a time: an account's
    // gate knows its server, the key reads the server's public settings.
    final keyReads =
        mediaType == 'tv' && lensId != null && (gate.grant?.isApiKey ?? false);
    final partialRequests =
        gate.server?.partialRequestsEnabled ??
        (keyReads &&
            (ref
                    .watch(seerrServerFactsProvider(lensId))
                    .value
                    ?.partialRequestsEnabled ??
                false));
    // A chip per season the request can still take, where the server takes
    // them one by one; otherwise the seasons it asks for, said.
    final picksSeasons = partialRequests && state.seasons.isNotEmpty;
    final seasonsTicked =
        state.seasons.isEmpty || state.selectedSeasons.isNotEmpty;

    Future<void> submit() async {
      final failure = await notifier.submitRequest(
        partialRequests: partialRequests,
        title: title,
      );
      if (!context.mounted) return;
      if (failure == null) {
        Navigator.pop(context);
        onRequestComplete();
        return;
      }
      if (failure.retryHelps) {
        SnackBarHelper.withAction(
          context,
          failure.message,
          actionLabel: Lexicon.retry,
          onAction: () => notifier.submitRequest(
            partialRequests: partialRequests,
            title: title,
          ),
        );
        return;
      }
      SnackBarHelper.error(context, failure.message);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (state.error != null &&
            state.errorReason == ServiceFailureReason.sessionEnded)
          // Signed out of Seerr: blue, the person's step, with the way back
          // into the connection's form. Never amber, never Retry.
          InlineErrorRetry(
            message: state.error!,
            error: const ClassifiedFailure(ServiceFailureReason.sessionEnded),
            service: ServiceKey.seerr,
            onRetry: notifier.reload,
          )
        else if (state.error != null)
          // Red only for a load nothing answered; a refusal, a failure that
          // did answer, or a Seerr with no server to send to is amber. The
          // glyph carries the tone, the sentence stays in the sheet's ink.
          state.errorDidNotAnswer
              ? FaultNote.unreachable(
                  message: state.error!,
                  surface: colorScheme.surfaceContainer,
                )
              : FaultNote.fault(
                  message: state.error!,
                  surface: colorScheme.surfaceContainer,
                )
        else if (!state.choosesDestination) ...[
          ..._titleOnly(
            context,
            state: state,
            notifier: notifier,
            gate: gate,
            kind: kind,
            quota: quota,
            submitVerdict: submitVerdict,
            picksSeasons: picksSeasons,
          ),
          SizedBox(
            width: double.infinity,
            child: RoleGatedAction.builder(
              verdict: submitVerdict,
              onTap: submit,
              builder: (context, onPressed, annotate) => FilledButton(
                // The sheet's one primary: `button-l`.
                style: AppTheme.primaryButtonStyle(context),
                onPressed: state.canSubmit && seasonsTicked ? onPressed : null,
                child: state.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : annotate(const Text('Submit request')),
              ),
            ),
          ),
        ] else ...[
          if (state.servers.length > 1) ...[
            Text('Server', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              key: ValueKey('request_server_${state.selectedServerId}'),
              isExpanded: true,
              initialValue: state.selectedServerId,
              items: state.servers
                  .map(
                    (server) => DropdownMenuItem(
                      value: server.id,
                      child: Text(server.choiceLabel),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  notifier.selectServer(value);
                }
              },
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Quality profile', style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<int>(
            key: ValueKey('request_profile_${state.selectedProfileId}'),
            isExpanded: true,
            initialValue: state.selectedProfileId,
            items: state.profiles
                .map(
                  (profile) => DropdownMenuItem(
                    value: profile.id,
                    child: Text(profile.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                notifier.selectProfile(value);
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          if (state.rootFolders.isNotEmpty) ...[
            Text('Root folder', style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: ValueKey('request_root_${state.selectedRootFolder}'),
              // A long path ellipsizes in the field rather than overflowing it.
              isExpanded: true,
              initialValue: state.selectedRootFolder,
              items: state.rootFolders
                  .map(
                    (folder) => DropdownMenuItem(
                      value: folder.path,
                      child: Text(folder.path),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  notifier.selectRootFolder(value);
                }
              },
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          ..._seasonChoices(context, state, notifier, picks: picksSeasons),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: AppTheme.primaryButtonStyle(context),
              onPressed: state.canSubmit && seasonsTicked ? submit : null,
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit request'),
            ),
          ),
        ],
        if (alternative case final other?) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                other.onTap();
              },
              child: Text(other.label),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  /// The sheet that sends the title alone: no server, no profile, no
  /// folder.
  List<Widget> _titleOnly(
    BuildContext context, {
    required RequestFormState state,
    required RequestFormNotifier notifier,
    required RoleGate gate,
    required SeerrMediaKind kind,
    required SeerrQuota? quota,
    required GateVerdict submitVerdict,
    required bool picksSeasons,
  }) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final brief = gate.faultVoice == FaultVoice.brief;
    final server = gate.server?.title ?? ServiceKey.seerr.title;
    // A choice of 4K only where both copies may be asked for and the account
    // and the server both take 4K; the copy alone otherwise.
    final choose4k = copies == SeerrRequestCopies.both && gate.offers4k(kind);
    final autoApproved =
        gate.grant?.may(
          state.is4k ? SeerrAbility.autoApproved4k : SeerrAbility.autoApproved,
          kind: kind,
        ) ??
        false;
    final status = quota?.of(kind);
    final quotaLeft = status == null
        ? null
        : brief
        ? RoleGateCopy.youQuotaLeft(status, kind)
        : RoleGateCopy.accountQuotaLeft(status, kind, server: server);
    // The operator holding an account that may not choose is told why the
    // pickers are not here; the requester never had them.
    final destination = gate.operatorAction(SeerrAbility.chooseDestination);

    return [
      Text('Quality', style: theme.textTheme.labelLarge),
      const SizedBox(height: AppSpacing.sm),
      if (choose4k)
        SelectionPills<bool>.wrap(
          values: const [false, true],
          selected: state.is4k,
          labelBuilder: (is4k) => is4k ? '4K' : 'Standard',
          onSelected: (is4k) => notifier.selectQuality(is4k: is4k),
        )
      else
        Text(state.is4k ? '4K' : 'Standard', style: theme.textTheme.bodyMedium),
      const SizedBox(height: AppSpacing.lg),
      ..._seasonChoices(context, state, notifier, picks: picksSeasons),
      Text(
        autoApproved ? Lexicon.startStraightAway : Lexicon.approvedByOwner,
        style: quiet,
      ),
      if (submitVerdict.reason ?? quotaLeft case final note?) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(note, style: quiet),
      ],
      if (destination.reason case final reason?) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(reason, style: quiet),
      ],
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  /// The seasons a request asks for: one chip per season it may still ask
  /// for where the server takes them one by one ([picks]), the ones ticked
  /// going; otherwise every one left, said. Nothing for a movie.
  List<Widget> _seasonChoices(
    BuildContext context,
    RequestFormState state,
    RequestFormNotifier notifier, {
    required bool picks,
  }) => [
    if (state.seasons.isNotEmpty) ...[
      Text('Seasons', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: AppSpacing.sm),
      if (picks)
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final season in state.seasons)
              FilterChip(
                label: Text('Season $season'),
                selected: state.selectedSeasons.contains(season),
                onSelected: (_) => notifier.toggleSeason(season),
              ),
          ],
        )
      else
        Text(
          Lexicon.seasons(state.seasons),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      const SizedBox(height: AppSpacing.lg),
    ],
  ];
}
