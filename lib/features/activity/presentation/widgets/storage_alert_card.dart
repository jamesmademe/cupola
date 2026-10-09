import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/features/activity/data/storage_alert_pool.dart';
import 'package:cupola/features/activity/domain/fault_words.dart';
import 'package:cupola/features/activity/domain/storage_fault.dart';
import 'package:cupola/features/activity/presentation/widgets/decision_fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show bringUnderLens;
import 'package:cupola/features/settings/domain/connection_presentation.dart'
    show writeFailureReason;
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/storage_api.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

/// A TrueNAS alert about a disk, on its card in Needs you: what the errors
/// mean for the disk's pool, and the scrub that repairs it.
///
/// The pool is read on the TrueNAS that raised the alert. Scrub tank asks
/// first, then the card says how far the scrub has got, read again every
/// minute while it runs. Open alert is always beside it. An alert that names
/// no disk, or a disk no pool holds, is the plain card with Open alert.
class StorageAlertCard extends ConsumerStatefulWidget {
  const StorageAlertCard({
    super.key,
    required this.decision,
    this.divided = false,
    this.whole = false,
  });

  final DashboardDecision decision;
  final bool divided;

  /// The Needs you page's card: a slab of its own, the pool's evidence.
  final bool whole;

  @override
  ConsumerState<StorageAlertCard> createState() => _StorageAlertCardState();
}

class _StorageAlertCardState extends ConsumerState<StorageAlertCard> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final decision = widget.decision;
    final disk = decision.subject;
    final plain = DecisionFaultCard(
      decision: decision,
      divided: widget.divided,
      whole: widget.whole,
    );
    if (disk == null) return plain;
    final key = (instanceId: decision.instanceId, disk: disk);
    final pool = ref.watch(storageAlertPoolProvider(key)).value;
    // Read again every minute while a scan runs, and only then.
    if (pool?.isScanning ?? false) {
      ref.watchWhileLive(context, storageScanPollProvider(key));
    }
    if (pool == null) return plain;

    final words = faultWordsOf(decision);
    final source = '${words.source} · pool ${pool.name}';
    final running = pool.isScanning
        ? (
            text: scanningLine(pool),
            progress: pool.scanPercentage == null
                ? null
                : pool.scanPercentage! / 100,
          )
        : null;
    final art = HomeRowArt.large(posterUrl: '', icon: decision.service.icon);
    final openAlert = (
      label: 'Open alert',
      onPressed: _openAlert,
      semanticLabel: 'Open the alert in TrueNAS',
    );
    final connectionId = decision.instanceId.isNotEmpty
        ? decision.instanceId
        : capabilityConnectionId(ref, ServiceKey.truenas);
    final scrub = CapabilityGatedAction.builder(
      service: ServiceKey.truenas,
      connectionId: connectionId,
      resource: TrueNasCapabilityArea.scrubRun.key,
      hint: trueNasCapabilityHint,
      blockedMessage: trueNasBlockedMessage('start a scrub'),
      onTap: () => _scrub(pool),
      builder: (context, onPressed, annotate) => SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _starting ? null : onPressed,
          style: remedyFillStyle(context),
          icon: const Icon(Icons.cleaning_services_rounded, size: 18),
          label: annotate(Text(scrubLabel(pool))),
        ),
      ),
    );

    return widget.whole
        ? FaultCard.whole(
            headline: words.headline,
            explanation: diskErrorsExplanation(disk, pool),
            source: source,
            why: words.why,
            art: art,
            evidence: poolEvidence(disk, pool),
            primary: scrub,
            running: running,
            secondary: [openAlert],
          )
        : FaultCard(
            headline: words.headline,
            explanation: diskErrorsExplanation(disk, pool),
            source: source,
            why: words.why,
            art: art,
            primary: scrub,
            running: running,
            secondary: [openAlert],
            divided: widget.divided,
          );
  }

  Future<void> _scrub(TrueNasPool pool) async {
    final ask = scrubConfirmation(pool);
    final answer = await showAppConfirmDialog(
      context: context,
      title: ask.title,
      message: ask.message,
      confirmLabel: ask.confirm,
      icon: Icons.cleaning_services_rounded,
    );
    if (!answer.confirmed || !mounted) return;
    setState(() => _starting = true);
    final decision = widget.decision;
    try {
      await TrueNasStorageApi(
        ref.read(truenasClientForProvider(decision.instanceId)),
      ).runScrub(pool.name);
    } catch (error) {
      if (mounted) {
        SnackBarHelper.error(
          context,
          'Could not start a scrub of ${pool.name}. '
          '${writeFailureReason(ServiceKey.truenas, error)}',
          cause: error,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _starting = false);
    }
    ref.invalidate(
      storageAlertPoolProvider((
        instanceId: decision.instanceId,
        disk: decision.subject!,
      )),
    );
  }

  Future<void> _openAlert() async {
    await bringUnderLens(ref, ServiceKey.truenas, widget.decision.instanceId);
    if (!mounted) return;
    context.go(ServiceRoutes.truenasDashboard);
  }
}
