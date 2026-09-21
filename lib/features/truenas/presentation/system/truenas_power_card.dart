import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_providers.dart';

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
                style: theme.textTheme.titleSmall!.weight(FontWeight.w700),
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
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmThenFire(
                    context,
                    ref,
                    hostname: hostname,
                    reboot: true,
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reboot…'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _confirmThenFire(
                    context,
                    ref,
                    hostname: hostname,
                    reboot: false,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                  label: const Text('Shut down…'),
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
    final ok = await _confirmByTypingHostname(
      context,
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
      confirmLabel: reboot ? 'Reboot' : 'Shut down',
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

/// A confirm whose button stays inert until the hostname is typed out.
///
/// The same control NPM's `confirmByTyping` already is, duplicated here rather
/// than imported: it lives in `features/npm/presentation/npm_actions.dart`, and
/// a TrueNAS screen reaching into another service's presentation layer is a
/// worse dependency than ninety lines. The shared move is slice 1 — one
/// `showTypedConfirmDialog` in `lib/core/widgets/app_dialog.dart`, which both
/// call sites and the Nginx block then read — and this function goes when it
/// lands.
Future<bool> _confirmByTypingHostname(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmLabel,
}) async {
  final controller = TextEditingController();
  final matches = ValueNotifier<bool>(false);
  // Trimmed and case-insensitive: hostnames are, and demanding exact case would
  // only teach people to copy-paste past the check.
  void update() {
    matches.value =
        controller.text.trim().toLowerCase() == phrase.trim().toLowerCase();
  }

  controller.addListener(update);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: statusToneColor(
            colorScheme,
            StatusTone.warning,
            surface: colorScheme.surface,
          ),
        ),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: SelectableText(
                phrase,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.weight(FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Type it to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: matches,
            builder: (context, enabled, _) => Semantics(
              // A disabled `FilledButton` publishes no hint of its own, so a
              // screen reader landing on it hears a dead button and no reason.
              hint: enabled ? null : 'Type $phrase above to enable',
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                onPressed: enabled
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text(confirmLabel),
              ),
            ),
          ),
        ],
      );
    },
  );

  controller.removeListener(update);
  controller.dispose();
  matches.dispose();
  return confirmed ?? false;
}
