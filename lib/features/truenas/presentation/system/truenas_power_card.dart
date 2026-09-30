import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

/// Reboot and Shut down, at the foot of the System section (decision 38).
///
/// The two controls in the app that end the session they are issued from, and
/// the only two nothing in Cupola can undo: once the host is down, the app
/// cannot wake it — only the physical power button or IPMI can. That asymmetry
/// is what the confirm has to carry, and why it asks for the hostname typed out
/// rather than a Yes: a tap is reversible muscle memory, a hostname is not
/// something you supply by accident on a scrolling page.
class TrueNasPowerCard extends ConsumerWidget {
  const TrueNasPowerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final info = ref.watch(truenasSystemInfoProvider);
    // The hostname is what the confirm asks to be typed, so without it there is
    // nothing to type and the card cannot promise its own guard. It draws
    // anyway — "—" rather than 0 or a blank, the same rule every unanswered
    // figure follows — and falls back to the service's own name as the phrase.
    final hostname = info.asData?.value?.hostname;

    return AppCard.surfaceOutlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.power_settings_new_rounded,
                size: 18,
                color: statusToneColor(
                  colorScheme,
                  StatusTone.warning,
                  surface: colorScheme.surface,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Power',
                style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Ends this connection. ${hostname ?? '—'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              // Gated on the probe alone: these two never see a reply, so
              // they cannot learn a refusal, and both are `FULL_ADMIN`-only,
              // which the probe reads without ambiguity. Gated at the tap that
              // opens the typed confirmation, never after the name is typed.
              Expanded(
                child: trueNasGatedButton(
                  ref: ref,
                  area: TrueNasCapabilityArea.power.key,
                  verbPhrase: 'reboot this server',
                  onTap: () => _confirmThenFire(
                    context,
                    ref,
                    hostname: hostname,
                    reboot: true,
                  ),
                  builder: (context, onPressed, annotate) => OutlinedButton(
                    onPressed: onPressed,
                    child: annotate(
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restart_alt_rounded, size: 18),
                          SizedBox(width: AppSpacing.sm),
                          Flexible(child: Text('Reboot…')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: trueNasGatedButton(
                  ref: ref,
                  area: TrueNasCapabilityArea.power.key,
                  verbPhrase: 'shut down this server',
                  onTap: () => _confirmThenFire(
                    context,
                    ref,
                    hostname: hostname,
                    reboot: false,
                  ),
                  // Neutral, like Reboot beside it. Nothing in this app can
                  // power the host back on, and the typed confirmation says
                  // so in words; red means unreachable and nothing else.
                  builder: (context, onPressed, annotate) => OutlinedButton(
                    onPressed: onPressed,
                    child: annotate(
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.power_settings_new_rounded, size: 18),
                          SizedBox(width: AppSpacing.sm),
                          Flexible(child: Text('Shut down…')),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmThenFire(
    BuildContext context,
    WidgetRef ref, {
    required String? hostname,
    required bool reboot,
  }) async {
    final phrase = hostname ?? 'TrueNAS';
    final ok = await showAppTypedConfirmDialog(
      context,
      icon: reboot
          ? Icons.restart_alt_rounded
          : Icons.power_settings_new_rounded,
      title: reboot ? 'Reboot $phrase?' : 'Shut down $phrase?',
      // The drawn copy. It enumerates instead of generalising because "this
      // will stop the server" is a sentence people read past; "the SMB · NFS ·
      // iSCSI shares and this connection" is one they picture.
      message: reboot
          ? 'Everything on this host stops while it restarts: apps, instances, '
                'the SMB · NFS · iSCSI shares and this connection. Cupola will '
                'not know when it is back, reopen this page to find out.'
          : 'Everything on this host stops: apps, instances, the SMB · NFS · '
                'iSCSI shares and this connection. Nothing in Cupola can bring '
                'it back, only the power button or IPMI can.',
      phrase: phrase,
      confirmLabel: reboot ? 'Reboot server' : 'Shut down server',
    );
    if (!ok || !context.mounted) return;

    final api = ref.read(truenasSystemApiProvider);
    runTrueNasDetachedAction(
      context,
      action: reboot ? api.reboot : api.shutdown,
      // Present tense, always. The socket dies before the host can confirm, so
      // "Rebooted" would be a claim nothing here is in a position to make.
      message: reboot ? 'Rebooting $phrase…' : 'Shutting down $phrase…',
    );
  }
}
