import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
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
/// The default constructor sizes itself to its message. Use
/// [InlineErrorRetry.fixedHeight] where the notice replaces a fixed-height slot
/// (a carousel row) and a self-sizing one would make the page jump.
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
/// certificate or an address the server may yet fix) both stay, the remedy first, on a row of their own under the sentence
/// so it keeps its width.
///
/// Whose form the remedy opens is [service], and [instanceId] when the caller
/// knows which connection the read went to (the lens's otherwise). A caller
/// that passes neither still gets the remedy through a fallback: the service
/// the message starts by naming, which `sectionFailureMessage` always does.
/// That is a reading of words, kept for the callers that do not pass a
/// service yet; a message that names none keeps Retry.
class InlineErrorRetry extends StatelessWidget {
  const InlineErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
    required this.error,
    this.service,
    this.instanceId,
  }) : _height = null;

  /// A notice locked to [_fixedHeight], for slots whose height must not change
  /// between the loading, loaded and failed states.
  const InlineErrorRetry.fixedHeight({
    super.key,
    required this.message,
    required this.onRetry,
    required this.error,
    this.service,
    this.instanceId,
  }) : _height = _fixedHeight;

  /// Height of the [InlineErrorRetry.fixedHeight] variant.
  static const double _fixedHeight = 120;

  final String message;
  final VoidCallback onRetry;

  /// What failed, classified for the glyph's tone. See the class comment. A
  /// null is a failure nobody can attribute: amber, never read as silence.
  final Object? error;

  /// Whose failure this is, for the remedy's form. Wins over the service the
  /// message names; see *The remedy leads*.
  final ServiceKey? service;

  /// The connection the failed read went to, when the caller knows it: the
  /// remedy opens that connection's form rather than the lens's.
  final String? instanceId;

  /// `null` for the self-sizing default; [_fixedHeight] for the fixed variant.
  final double? _height;

  @override
  Widget build(BuildContext context) {
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
    final fault = failureIsFault(reason);
    final verbs = [
      if (remedy != null)
        FilledButton(
          onPressed: () => remedy.open(context),
          style: remedyFillStyle(context, compact: true),
          child: Text(remedy.label),
        ),
      if (remedy == null && fault)
        FilledButton(
          onPressed: onRetry,
          style: remedyFillStyle(context, compact: true),
          child: const Text(Lexicon.retry),
        )
      else if (remedy == null || remedy.retryHelps)
        TextButton(
          onPressed: onRetry,
          style: _verbStyle(colorScheme),
          child: const Text(Lexicon.retry),
        ),
    ];
    // In the fixed slot the second row of verbs takes the height a third line
    // of the sentence would need, so the sentence stops at two there. The
    // screen reader still hears all of it: the label is the whole message.
    final clipped = _height != null && verbs.length > 1;
    final sentence = ExcludeSemantics(
      child: Text(
        message,
        maxLines: clipped ? 2 : null,
        overflow: clipped ? TextOverflow.ellipsis : null,
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final glyphMark = ExcludeSemantics(
      child: Icon(glyph, size: 16, color: alarm),
    );

    return Container(
      width: double.infinity,
      height: _height,
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
        child: verbs.length == 1
            ? Row(
                children: [
                  glyphMark,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: sentence),
                  const SizedBox(width: AppSpacing.sm),
                  verbs.single,
                ],
              )
            // Two verbs beside the sentence would leave it a third of the
            // line on a phone, so they take the row under it, at the trailing
            // edge where the one verb sits otherwise.
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      glyphMark,
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: sentence),
                    ],
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.xs,
                    children: verbs,
                  ),
                ],
              ),
      ),
    );
  }

  static ButtonStyle _verbStyle(ColorScheme colorScheme) =>
      TextButton.styleFrom(
        // Rule 2. Brand primary, never the error tone.
        foregroundColor: colorScheme.primary,
        // 44pt on iOS / 48dp on Android is the floor, and this button shares
        // its row with body text that would otherwise size it. Standard
        // density, pinned: compact silently takes 8 off `minimumSize`, and 44
        // declared measured 40.
        visualDensity: VisualDensity.standard,
        minimumSize: const Size(56, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      );
}
