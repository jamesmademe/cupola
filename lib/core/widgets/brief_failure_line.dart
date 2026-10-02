import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Builds a failure in the voice of who the app is for: [full], the whole
/// classification, for the operator; [brief], one line, for the requester.
///
/// The audience is read only inside a provider scope, which the app always
/// has; a bare widget test of a failure state draws the operator's.
class FaultVoiceSwitch extends StatelessWidget {
  const FaultVoiceSwitch({super.key, required this.full, required this.brief});

  final WidgetBuilder full;
  final WidgetBuilder brief;

  @override
  Widget build(BuildContext context) {
    if (!_scoped(context)) return full(context);
    return Consumer(
      builder: (context, ref, _) =>
          _audience(ref) == Audience.requester ? brief(context) : full(context),
    );
  }

  static bool _scoped(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A scope with no settings in it (a test that overrides something else)
  /// is the operator's.
  static Audience _audience(WidgetRef ref) {
    try {
      return ref.watch(audienceProvider);
    } catch (_) {
      return Audience.operator;
    }
  }
}

/// A failure as the requester reads it: one line with its time, and `Retry`
/// where the same request can still succeed.
///
/// She never reads a service's name (Jellyfin and Plex excepted, the players
/// she watches with), a refused key, a certificate or a status code: whatever
/// the cause, the server cannot be reached, `Can't reach the server since
/// 20:41`, red only when nothing answered and amber otherwise, as the tone
/// rule says. The time is when this line first appeared, so a Retry that fails
/// again keeps it. A session that ended is the one cause she can act on, and
/// says so: `You were signed out` with `Sign in again`.
///
/// Two shapes: [BriefFailureLine.line] where a section's content would be,
/// [BriefFailureLine.page] where a page's would.
class BriefFailureLine extends StatefulWidget {
  const BriefFailureLine.line({
    super.key,
    required this.error,
    required this.onRetry,
    this.service,
    this.instanceId,
  }) : _page = false;

  const BriefFailureLine.page({
    super.key,
    required this.error,
    required this.onRetry,
    this.service,
    this.instanceId,
  }) : _page = true;

  /// What failed, classified for the tone and for whether it was a session
  /// that ended.
  final Object? error;

  /// Sends the same request again; offered only where it can still succeed.
  final VoidCallback? onRetry;

  /// Whose failure this is: named only when the requester may read it, and
  /// the form `Sign in again` opens.
  final ServiceKey? service;

  /// The connection the failed read went to, for `Sign in again`.
  final String? instanceId;

  final bool _page;

  /// The line itself: the requester's words for [reason], with [since] as the
  /// time the server stopped answering.
  static ({String headline, String? sentence}) wordsFor(
    ServiceFailureReason reason, {
    required DateTime since,
    ServiceKey? service,
  }) {
    if (reason == ServiceFailureReason.sessionEnded) {
      return (
        headline: Lexicon.youWereSignedOut,
        sentence: Lexicon.signInToKeepAsking,
      );
    }
    final subject = switch (service) {
      ServiceKey.jellyfin || ServiceKey.plex => service!.title,
      _ => 'the server',
    };
    return (
      headline: Lexicon.cantReachSince(subject, formatClockTime(since)),
      sentence: null,
    );
  }

  @override
  State<BriefFailureLine> createState() => _BriefFailureLineState();
}

class _BriefFailureLineState extends State<BriefFailureLine> {
  late final DateTime _since = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = classifyConnectionFailure(widget.error);
    final words = BriefFailureLine.wordsFor(
      reason,
      since: _since,
      service: widget.service,
    );
    final ended = reason == ServiceFailureReason.sessionEnded;
    final tone = statusToneColor(
      colorScheme,
      failureTone(reason),
      surface: colorScheme.surface,
    );
    final verbs = _verbs(context, reason, ended: ended);
    final spoken = [words.headline, ?words.sentence].join('. ');

    if (widget._page) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            liveRegion: true,
            label: spoken,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(failureIcon(reason), size: 32, color: tone),
                ),
                const SizedBox(height: AppSpacing.lg),
                ExcludeSemantics(
                  child: Text(
                    words.headline,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium!
                        .weight(FontWeight.w600)
                        .copyWith(color: tone),
                  ),
                ),
                if (words.sentence case final sentence?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ExcludeSemantics(
                    child: Text(
                      sentence,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ),
                ],
                if (verbs.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  Wrap(spacing: AppSpacing.sm, children: verbs),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        liveRegion: true,
        label: spoken,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(failureIcon(reason), size: 16, color: tone),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  spoken.endsWith('.') ? spoken : '$spoken.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            for (final verb in verbs) ...[
              const SizedBox(width: AppSpacing.sm),
              verb,
            ],
          ],
        ),
      ),
    );
  }

  /// `Sign in again` after an ended session, into the account's own form;
  /// `Retry` where the same request can still succeed; nothing else.
  List<Widget> _verbs(
    BuildContext context,
    ServiceFailureReason reason, {
    required bool ended,
  }) {
    if (ended) {
      final remedy = FailureRemedy.forReason(
        widget.service ?? ServiceKey.seerr,
        ServiceFailureReason.sessionEnded,
        instanceId: widget.instanceId,
      );
      if (remedy == null) return const [];
      return [
        FilledButton(
          onPressed: () => remedy.open(context),
          style: remedyFillStyle(context, compact: true, fault: false),
          child: Text(remedy.label),
        ),
      ];
    }
    final retry = widget.onRetry;
    if (retry == null || !failureRetryHelps(reason)) return const [];
    return failureLineVerbs(
      context,
      remedy: null,
      fault: failureIsFault(reason),
      onRetry: retry,
    );
  }
}
