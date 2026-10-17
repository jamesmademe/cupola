import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What this credential cannot do, said once, at the top of the page.
///
/// The same line as [InlineErrorRetry] and [FaultBand]: no fill, no border,
/// one 16pt glyph, a sentence in `onSurfaceVariant`, one verb in brand
/// primary, in the one tone none of them uses.
///
/// ## Why it is blue
///
/// Because nothing is wrong. An Unraid key issued without write permissions, a
/// TrueNAS key whose user holds only read roles, an NPM login with a view-only
/// role: in every case the credential is working exactly as it was created,
/// and the app is reporting a **configuration fact**. Amber would put it in the
/// same bucket as a stalled transfer and a failing indexer, which is a
/// category error the user pays for; they would go looking for a fault that
/// does not exist. Under the tone rule blue is "informational", and this is
/// the definition of it.
///
/// It is also why the banner does not dismiss. There is nothing to acknowledge:
/// the scope is still what it is a second later, and the controls below are
/// still dimmed. The only thing that changes it is a new credential, which is
/// what the action offers.
///
/// ## Why it is not announced
///
/// It used to be a live region, on the reasoning that it changes what every
/// control below it will do. That was reversed once the scope came from a
/// probe per credential: the banner is then drawn on **every visit** to every
/// page of a read-only connection, and a live region would interrupt each of
/// those visits with the same two sentences. It is a standing state of the
/// connection, not an event: read when the user reaches it, like any other
/// text, and the dimmed controls carry the same fact in their hints exactly
/// where it matters, on the control about to be pressed.
///
/// ## What it does not do
///
/// It does not hide the writes it describes, and it does not stop the readouts.
/// A read-only connection still reads perfectly well, so the page keeps
/// refreshing and every write below dims to 38% through [CapabilityGatedAction]
/// while staying reachable. The banner exists so that dimming has an
/// explanation the user can find without pressing anything.
class CapabilityBanner extends StatelessWidget {
  const CapabilityBanner({
    super.key,
    required this.message,
    required this.onFix,
    this.actionLabel = 'Update the key',
  });

  /// What this credential cannot do, in the user's terms and in its own words:
  /// *"This Unraid key can read. Starting and stopping VMs needs a key with
  /// write access to VMs."* Two sentences: what it can do, then what it
  /// cannot, because a banner that only lists the refusals reads as breakage.
  ///
  /// The caller writes it (through a `CapabilityCopy`): the scope names differ
  /// per service and a generic "limited permissions" would tell nobody which
  /// setting to change.
  final String message;

  /// The fix. Lands on the page where that connection's credential is
  /// replaced, or, when Cupola could not ask, asks again.
  final VoidCallback onFix;

  /// Overridable for the services whose credential is not a key: NPM hands out
  /// a *role*, and "Update the key" would send the user looking for a field
  /// that does not exist, and for *Check again*.
  final String actionLabel;

  /// Above this reading scale the action goes on its own line.
  ///
  /// A `Row` of glyph, sentence and button overflows at large reading sizes: a
  /// `TextButton` is not flexible, so the action laid out at three times its
  /// normal width takes more room than the row has and the `Expanded` beside
  /// it cannot give any more away. Shrinking the button is not an option: it
  /// is a 44pt target with a name that has to stay readable; so past this
  /// scale the layout stacks instead. It is the clamp
  /// `TextScaleMetrics.defaultMaxScaleFactor` uses for the boxes it grows,
  /// applied to the size the sentence is actually drawn at (the `bodySmall`
  /// role), so the threshold follows the role rather than a copy of its size.
  /// The NPM access band carried this first.
  static const double stackScale = TextScaleMetrics.defaultMaxScaleFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // `StatusTone.info`, resolved through the same walk every other tone takes:
    // raw blue measures about 3.3:1 on the light scaffold, and with no fill
    // behind it this glyph is the only thing carrying the tone.
    final glyph = statusToneColor(
      colorScheme,
      StatusTone.info,
      surface: colorScheme.surface,
    );

    final icon = ExcludeSemantics(
      child: Icon(Icons.key_outlined, size: 16, color: glyph),
    );
    final text = ExcludeSemantics(
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final action = TextButton(
      onPressed: onFix,
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        // No `VisualDensity.compact`: it silently takes 8 off `minimumSize`,
        // and 44 declared measured 40.
        minimumSize: const Size(56, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: Text(actionLabel),
    );

    // The measure is the sentence's own role, so what is compared is what is
    // drawn.
    final measure =
        theme.textTheme.bodySmall?.fontSize ??
        DesignTokens.typeBodySmallFontSize;
    final stacked =
        MediaQuery.textScalerOf(context).scale(measure) > measure * stackScale;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Semantics(
        container: true,
        // The fix stays its own control; this node owns the sentence.
        explicitChildNodes: true,
        label: message,
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: text),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              )
            : Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: text),
                  const SizedBox(width: AppSpacing.sm),
                  action,
                ],
              ),
      ),
    );
  }
}

/// Where a page's [CapabilityBanner] goes, and whether it has anything to say.
///
/// One per page, **the first thing under the page's own chrome, above the
/// first section**. It watches the connection's grant and renders nothing
/// unless the credential is restricted for one of [resources], so a
/// read-write key, an unprobed connection and a page whose writes this
/// credential may make all draw no banner at all.
///
/// The sentence follows why the scope is what it is: the service's answer, a
/// refusal learned in this session, or Cupola not having been able to ask. The
/// last is the only one whose action is *Check again*; a view-only account is
/// not a transient failure, and offering to re-check it would suggest the
/// answer might change.
class CapabilityBannerSlot extends ConsumerWidget {
  const CapabilityBannerSlot({
    super.key,
    required this.connectionId,
    required this.copy,
    this.resources,
  });

  /// Whose credential this is. See `capabilityConnectionId`.
  final String connectionId;

  /// The page's sentences. Its service names the fix verb and the credential.
  final CapabilityCopy copy;

  /// The resources this page writes. Null: the banner appears only when the
  /// connection as a whole is restricted.
  final Set<String>? resources;

  ServiceKey get _service => copy.service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grant = ref.watch(capabilityGrantForProvider(connectionId));
    if (!grant.restrictsAny(resources)) return const SizedBox.shrink();

    final restricted = {
      for (final resource in resources ?? const <String>{})
        if (grant.scopeFor(resource).isRestricted) resource,
    };

    if (grant.basis == CapabilityBasis.unanswered) {
      return CapabilityBanner(
        message: copy.bannerFor(grant, restricted),
        actionLabel: 'Check again',
        onFix: () => recheckCapability(ref, connectionId),
      );
    }
    return CapabilityBanner(
      message: copy.bannerFor(grant, restricted),
      actionLabel: _service.capabilityFixLabel,
      onFix: () => context.push(
        ServiceRoutes.settingsForConnection(_service, connectionId),
      ),
    );
  }
}
