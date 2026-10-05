import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/media/domain/media_facts.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';

/// A request for the title that waits for approval, answered from its page:
/// who asked and when, then Approve and Decline, in the order and the weight
/// of the approval sheet.
///
/// When nothing else leads (the title is on no server yet), the card takes
/// the lead's place and Approve is the page's one lit fill ([leads]);
/// under a lead that plays or fixes a copy, it is quiet.
///
/// Both answers go through [ActivityActions], the app's one Seerr write
/// path: its question says where an approved request goes, and a request
/// someone answered meanwhile is told apart. [onDecided] then reads the page
/// again.
class MediaDecisionCard extends ConsumerWidget {
  const MediaDecisionCard({
    super.key,
    required this.pending,
    required this.title,
    required this.leads,
    required this.onDecided,
    this.light,
  });

  final MediaPendingRequest pending;

  /// What the question calls the title.
  final String title;

  /// Whether Approve leads the page, lit by [light].
  final bool leads;
  final TitleLight? light;
  final VoidCallback onDecided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final seerr = pending.seerr.id;
    final request = pending.request;
    final gate = ref.watch(roleGateProvider(seerr));
    final decide = gate.operatorAction(SeerrAbility.approve);
    // Who asked, where the connection sees everyone's requests.
    final who = gate.showsRequesterNames
        ? request.requestedBy?.displayName
        : null;
    final headline = mediaDecisionHeadline(request, who: who);
    final waiting = [
      StateWord.waitingForApproval.label,
      formatRelativeActivityDate(request.createdAt),
    ].join(' · ');
    final info = statusToneColor(
      scheme,
      StatusTone.info,
      surface: room.fillQuiet,
    );

    Future<void> answer({required bool approve}) async {
      if (approve) {
        await ActivityActions.approveRequest(
          context,
          ref,
          instanceId: seerr,
          requestId: request.id,
          title: title,
          request: request,
        );
      } else {
        await ActivityActions.declineRequest(
          context,
          ref,
          instanceId: seerr,
          requestId: request.id,
          title: title,
        );
      }
      onDecided();
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              headline,
              style: AppType.section.copyWith(color: room.ink),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: info, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  waiting,
                  style: AppType.label.copyWith(color: info),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          RoleGatedAction.builder(
            verdict: decide,
            onTap: () => answer(approve: true),
            builder: (context, onPressed, annotate) => FilledButton(
              onPressed: onPressed,
              style: leads
                  ? mediaLeadStyle(context, light)
                  : FilledButton.styleFrom(
                      backgroundColor: room.fillStrong,
                      foregroundColor: room.ink,
                    ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SeerrApprovalGlyph(
                    instanceId: seerr,
                    requestId: request.id,
                    size: 20,
                    idle: const Icon(Icons.check_rounded, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  annotate(const Text('Approve')),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          RoleGatedAction.builder(
            verdict: decide,
            onTap: () => answer(approve: false),
            builder: (context, onPressed, annotate) => OutlinedButton(
              onPressed: onPressed,
              child: annotate(const Text('Decline')),
            ),
          ),
        ],
      ),
    );
  }
}
