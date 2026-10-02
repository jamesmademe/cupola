import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/beside_or_below.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';

/// Inline failure notice with a retry action, so a failed section reads as a
/// failure rather than as an endless loading shimmer.
///
/// Every service dashboard grows sections that load independently, and a
/// section that fails must not take the whole page down: this line sits in the
/// slot the content would have occupied and offers the retry right there.
///
/// It sizes itself to its message. A fixed-height variant for a carousel row
/// went unused and clipped its sentence at a large text size; it is gone.
///
/// ## Why it is a line and not a card
///
/// It used to be a filled, bordered card: `errorContainer` at 40% behind an
/// `error` stroke at 50%, with the sentence in `onErrorContainer`. That is the
/// chrome of an alarm, and in a self-hosted stack a section that did not load
/// is a Tuesday — the download client is rebuilding, the indexer is rate
/// limited, the box is off. A page that shouts on every open is a page whose
/// shouting stops being read.
///
/// So the notice keeps its **presence** as the signal and gives up its volume:
/// no fill, no border, the sentence in `onSurfaceVariant`, and the error tone
/// spent on exactly one 16pt glyph. Three rules govern every failure surface in
/// the app and this widget is the smallest of them:
///
///  1. presence is the signal — no fill, no border, the error tone on the glyph
///     and nowhere else;
///  2. the recovery verb is never painted in the error tone — a red Retry makes
///     the cure look like the disease, so beside silence it is the primary
///     ink. An amber fault's remedy is the one fill a fault gets: the amber
///     fill ([remedyFillStyle]), as a compact control on the line;
///  3. nothing is dimmed for being unreachable, because dimming means *not
///     configured* everywhere else on this canvas.
///
/// [CapabilityBanner] is deliberately the same shape in a different tone: a
/// credential that may only read is configuration, not a fault. It could not
/// have copied this widget while this widget still carried error chrome.
///
/// ## Tone follows the cause
///
/// The [error] that failed is required, and the glyph takes the
/// classification's tone and glyph: red only when nothing answered, amber for
/// a refusal or any other failure that did answer. It used to be optional,
/// and every section that left it out stayed red for any failure — a refused
/// key read exactly like a switched-off box. Word the [message] from the same
/// classification (`sectionFailureMessage`), so the glyph and the sentence
/// cannot disagree.
///
/// ## The remedy leads
///
/// The same classification decides the verb. A cause whose fix lives in the
/// connection's form offers that fix ([FailureRemedy]) in place of Retry: a
/// refused key reads `Paste the key again` and opens the form, and Retry is
/// left out because the same key can only be refused again. Where the same
/// request can still succeed (a refused sign-in whose ban runs out, a
/// certificate or an address the server may yet fix) both stay, the remedy
/// first. The verbs sit beside the sentence while it keeps sixteen of its own
/// em, and go under it otherwise ([BesideOrBelow]), so it keeps its width.
///
/// Whose form the remedy opens is [service], and [instanceId] when the caller
/// knows which connection the read went to (the lens's otherwise). Every
/// caller in `lib/` passes [service], and `failure_service_guard_test.dart`
/// holds it there: the words cannot name a connection the user renamed, nor
/// tell two Radarrs apart.
///
/// Without one the notice falls back to the service the message starts by
/// naming, which `sectionFailureMessage` always does. That fallback is a
/// reading of words, kept so a notice drawn without a service still offers
/// the fix; nothing in the app relies on it, and a message that names no
/// service keeps Retry.
class InlineErrorRetry extends StatelessWidget {
  const InlineErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
    required this.error,
    this.service,
    this.instanceId,
  });

  final String message;
  final VoidCallback onRetry;

  /// What failed, classified for the glyph's tone. See the class comment. A
  /// null is a failure nobody can attribute: amber, never read as silence.
  final Object? error;

  /// Whose failure this is, for the remedy's form. Wins over the service the
  /// message names; see *The remedy leads*. Optional only for that fallback:
  /// every call in `lib/` passes it.
  final ServiceKey? service;

  /// The connection the failed read went to, when the caller knows it: the
  /// remedy opens that connection's form rather than the lens's.
  final String? instanceId;

  /// The requester reads one line with its time ([BriefFailureLine]),
  /// never this classification; see `RoleGate.faultVoice`.
  @override
  Widget build(BuildContext context) => FaultVoiceSwitch(
    full: _full,
    brief: (context) => BriefFailureLine.line(
      error: error,
      onRetry: onRetry,
      service: service ?? FailureRemedy.serviceNamedBy(message),
      instanceId: instanceId,
    ),
  );

  Widget _full(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reason = classifyConnectionFailure(error);

    // Walked against the surface itself, because the raw error red measures
    // around 3.4:1 on the light scaffold, and with the fill gone this glyph is
    // the only thing carrying the tone. A graphical object owes 3:1 and has no
    // coloured text beside it to lean on.
    final alarm = statusToneColor(
      colorScheme,
      failureTone(reason),
      surface: colorScheme.surface,
    );
    final glyph = failureIcon(reason);
    final remedy = FailureRemedy.of(
      service ?? FailureRemedy.serviceNamedBy(message),
      error,
      instanceId: instanceId,
    );
    // The remedy of a fault, the form's fix or Retry when retrying is the
    // fix, wears the amber fill: the Presence Rule gives the line exactly one
    // fill and puts it there, and amber words on the verb would spend the tone
    // the rule keeps for the glyph. Retry beside a remedy, and Retry beside
    // silence, stay text in ink.
    final verbs = failureLineVerbs(
      context,
      remedy: remedy,
      fault: failureIsFault(reason),
      onRetry: onRetry,
    );
    final style = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final em = MediaQuery.textScalerOf(context).scale(style?.fontSize ?? 12);
    final sentence = ExcludeSemantics(child: Text(message, style: style));
    // On the sentence's first line, so a sentence that wraps keeps its mark
    // where the reading starts.
    final glyphMark = Padding(
      padding: EdgeInsets.only(
        top: math.max(0, (em * (style?.height ?? 1.4) - _glyphSize) / 2),
      ),
      child: ExcludeSemantics(
        child: Icon(glyph, size: _glyphSize, color: alarm),
      ),
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        container: true,
        // Retry stays its own control; this node owns the sentence only.
        explicitChildNodes: true,
        // Announced when it appears, which is the moment it matters. Not routed
        // through `announce()` as well: that double-reads on iOS.
        liveRegion: true,
        label: message,
        child: BesideOrBelow(
          gap: AppSpacing.sm,
          minLead:
              BesideOrBelow.sentenceMeasure(em) + _glyphSize + AppSpacing.sm,
          lead: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              glyphMark,
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: sentence),
            ],
          ),
          trailing: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            children: verbs,
          ),
        ),
      ),
    );
  }
}

const double _glyphSize = 16;
