import 'package:flutter/material.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/percent_format.dart';

export 'package:cupola/core/status/media_status.dart';

/// Renders a resolved [MediaStatusInfo].
///
/// The badge no longer derives anything: the status arrives fully resolved from
/// a per-service resolver in the feature's `domain/` layer. That is deliberate —
/// when the derivation lived here, each caller passed a different `status`
/// string and an item being downloaded rendered as `Missing`.
class StatusBadge extends StatelessWidget {
  final MediaStatusInfo info;

  /// Poster-overlay variant: filled with the tone colour, icon only (plus the
  /// download percentage when known).
  final bool compact;

  /// An 8px tone-coloured dot, for dense poster rails.
  final bool iconOnly;

  /// Suppresses this badge's own semantics node.
  ///
  /// Set it when an enclosing tile already speaks the status — a poster cell
  /// passing `info.semanticLabel` as its `semanticValue`, say. Without it the
  /// tile and the badge are two stops for one piece of information; with it the
  /// badge is decoration, which is what a coloured dot on a poster is.
  final bool excludeFromSemantics;

  /// Whether status changes animate. A new resolved status cross-fades the
  /// badge's content — glyph, label and percentage together — through an
  /// [AnimatedSwitcher], so the tone changes only as the old glyph fades out
  /// and the new one fades in; no colour is tweened. The progress ring sweeps
  /// to each new value rather than snapping. The pill does not resize
  /// smoothly: during the fade it holds the wider of the two contents, and the
  /// width jumps to the new one when the fade ends.
  ///
  /// Only the `.animated` constructor sets this — the
  /// default badge stays static because it appears on twenty-odd surfaces
  /// (poster overlays, queue rows, activity feeds) where a per-cell animation
  /// would be noise.
  final bool _animated;

  /// Set only by [StatusBadge.poster].
  final bool _poster;

  const StatusBadge({
    super.key,
    required this.info,
    this.compact = false,
    this.iconOnly = false,
    this.excludeFromSemantics = false,
  }) : _animated = false,
       _poster = false;

  /// The word on a catalogue poster: a dot in the tone and the state word
  /// (or the percentage, while bytes arrive) on the plate, so a grid of
  /// posters reads without a legend. Between [compact], which is a glyph a
  /// reader has to learn, and the full badge, whose icon a poster corner
  /// has no room for. A word too long for the poster wraps to a second line
  /// inside the plate rather than losing its end.
  const StatusBadge.poster({
    super.key,
    required this.info,
    this.excludeFromSemantics = false,
  }) : compact = false,
       iconOnly = false,
       _animated = false,
       _poster = true;

  /// Full badge that cross-fades between resolved statuses and sweeps its
  /// progress ring (see [_animated] for exactly what moves). Used on the media
  /// detail hero, where a single badge changing
  /// state (missing → downloading → available) is the point of the surface.
  /// Renders identically to the default under Reduce Motion.
  const StatusBadge.animated({
    super.key,
    required this.info,
    this.excludeFromSemantics = false,
  }) : compact = false,
       iconOnly = false,
       _animated = true,
       _poster = false;

  /// The poster word's dot, a step under the dense rail's 8: it sits beside
  /// a word, not alone on the artwork.
  static const double _posterDot = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cupolaColors =
        theme.extension<CupolaThemeColors>() ??
        CupolaThemeColors.defaults(
          brightness: theme.brightness,
          colorScheme: colorScheme,
        );

    final accentColor = statusToneColor(colorScheme, info.tone);
    // Compact or not, the badge is the plate with the tone on its glyph: only
    // an amber fault's remedy is filled with a tone (brand book, *The tone
    // rule*). The compact one was the tone at 90%, a fill on every poster.
    final backgroundColor = cupolaColors.statusBadgeBackground;
    final borderColor = cupolaColors.statusBadgeForeground.withValues(
      alpha: 0.12,
    );
    final textColor = cupolaColors.statusBadgeForeground;

    if (iconOnly) {
      return _spoken(
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: accentColor,
            shape: BoxShape.circle,
            // A separator ring, not a depth level — this is why it is a single
            // `BoxShadow` rather than an `AppElevation` stack. An 8px mark sits
            // directly on arbitrary poster artwork in a dense row, and without a
            // ring a tone-coloured dot can land on artwork of its own tone and
            // vanish. `colorScheme.shadow` is the token for exactly this ink
            // (black in the dark scheme, the primary ink on paper, as every
            // other shadow in the room) and keeps the file inside the
            // no-raw-`Colors` rule; the back button that used to be cited as the
            // earned exception here no longer holds one.
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.35),
                spreadRadius: 1.5,
              ),
            ],
          ),
        ),
      );
    }

    if (_poster) {
      final percent = _percentText;
      return _spoken(
        Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s,
            AppSpacing.xxs,
            AppSpacing.sm,
            AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.thumb),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The tone lives on the dot alone, as on every badge's glyph:
              // the word stays in the plate's ink.
              Container(
                width: _posterDot,
                height: _posterDot,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  percent ?? info.label,
                  maxLines: 2,
                  style: percent != null
                      ? theme.textTheme.labelSmall!
                            .weight(FontWeight.w600)
                            .tabular
                            .copyWith(color: textColor)
                      : theme.textTheme.labelSmall!
                            .weight(FontWeight.w600)
                            .copyWith(color: textColor),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final foreground = accentColor;
    final percentText = _percentText;
    final animate = _animated && !MediaQuery.disableAnimationsOf(context);

    // **Nothing in this badge rolls, and that is a decision rather than an
    // omission** — it is the one surface in the app where a state word genuinely
    // changes and is deliberately left alone.
    //
    // The label was rolled on `.animated` and reverted. This badge is the only
    // reel candidate whose surface *already* had a considered animation: a keyed
    // cross-fade of the whole content and a swept progress ring, tuned together
    // for a badge whose changing state is the point of the page. A roll on top
    // of those is a third treatment competing with two that work —
    // motion added because it was available, not because anything was missing.
    // It also does not pay for itself: `ReelText` renders one `Text` per
    // grapheme, so rolling the label scattered single-letter `Text` widgets over
    // every detail page, enough to make `find.text('R')` match a slot inside a
    // test asserting a certification is *not* drawn as its own text.
    //
    // The percentage is a separate and firmer no. It updates on every poll while
    // bytes move, so rolling it would leave a queue of eight rows permanently in
    // motion on a two-second clock. A state word changes when the thing it names
    // changes; digits change because time passed. `.tabular` is the right fix for
    // a live number, and it is already applied.
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      // Keyed by the resolved state (not the live percentage) so the switcher
      // fires on a status change without restarting every progress tick.
      key: animate
          ? ValueKey('${info.availability}-${info.pipeline}-${info.label}')
          : null,
      children: [
        _leading(size: compact ? 10 : 12, color: foreground, animate: animate),
        if (!compact) ...[
          const SizedBox(width: AppSpacing.xs),
          // Flexible: a label wider than its place wraps inside the badge
          // rather than running out of it. A state word cut short loses the
          // state; on two lines it is still read.
          Flexible(
            child: Text(
              info.label,
              style: theme.textTheme.labelSmall!
                  .weight(FontWeight.w600)
                  .copyWith(color: textColor),
            ),
          ),
        ],
        if (percentText != null) ...[
          SizedBox(width: compact ? 2 : AppSpacing.xs),
          Text(
            percentText,
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w600)
                .tabular
                .copyWith(color: textColor),
          ),
        ],
      ],
    );
    if (animate) {
      content = AnimatedSwitcher(
        duration: AppAnimation.durationSm,
        switchInCurve: AppAnimation.emphasizedCurve,
        child: content,
      );
    }

    Widget badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: compact ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: content,
    );

    return _spoken(badge);
  }

  /// One spoken form for all three variants.
  ///
  /// The `iconOnly` dot is pure colour and the `compact` overlay is colour plus
  /// a glyph, so neither has anything to read. Even the full badge paints only
  /// [MediaStatusInfo.label] and a percentage — the warning carried by the tone
  /// is never written down. So the string always comes from
  /// [MediaStatusInfo.semanticLabel] and the painted children are excluded,
  /// which keeps one code path instead of three and stops the full badge
  /// announcing the same pill twice over.
  ///
  /// No `button:` role: in every call site the tap lives on the enclosing tile.
  Widget _spoken(Widget badge) {
    if (excludeFromSemantics) return ExcludeSemantics(child: badge);

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: info.semanticLabel,
      child: badge,
    );
  }

  /// A determinate ring while bytes are moving, the state icon otherwise.
  ///
  /// When [animate] is set, the ring sweeps to each new value instead of
  /// snapping — the digits beside it stay live and honest, only the arc
  /// eases. A count-up on the numbers themselves was considered and
  /// rejected: a percentage that lags the actual transfer is briefly wrong
  /// on purpose.
  Widget _leading({
    required double size,
    required Color color,
    bool animate = false,
  }) {
    if (info.isActive && info.progress != null) {
      final ring = animate
          ? TweenAnimationBuilder<double>(
              tween: Tween<double>(end: info.progress),
              duration: AppAnimation.durationMd,
              curve: AppAnimation.standardCurve,
              builder: (context, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 2,
                color: color,
                backgroundColor: color.withValues(alpha: 0.25),
              ),
            )
          : CircularProgressIndicator(
              value: info.progress,
              strokeWidth: 2,
              color: color,
              backgroundColor: color.withValues(alpha: 0.25),
            );
      return SizedBox(width: size, height: size, child: ring);
    }

    return Icon(statusIconFor(info), size: size, color: color);
  }

  String? get _percentText {
    final percent = info.progressPercent;
    return percent == null ? null : formatPercent(percent);
  }
}

/// The single mapping from a semantic [StatusTone] to a real colour.
///
/// Top-level rather than private to the badge because a status is not always
/// drawn *as* a badge: a queue row tints its progress bar by tone so a failed
/// transfer reads red instead of the service accent, and the Activity feed tints
/// its leading icon well the same way. Every one of those was previously a
/// widget-local `switch` on something other than the resolved status — which is
/// how a `downloadFailed` event ended up rendering in the success green.
///
/// Anything that colours by status calls this. Nothing re-derives it.
///
/// Each room has its own five tones — the dark room's bright ones, the day
/// room's deep ones — and the tone is taken from the room [colorScheme]
/// belongs to. It is then *walked* against [surface] the same way a service
/// accent is, because a tone verified on one ground is not verified on the
/// others: the day room's green measures 4.91:1 on paper but 4.45:1 on the
/// chip fill, and less again on its own 16% wash. The walk keeps the hue and
/// moves only the lightness, so a failed transfer is still red, just a red that
/// can be read.
///
/// Callers used to do this themselves where someone had noticed — the expanded
/// service card carried the idiom and a comment explaining it. Sixteen other
/// files did not, which is the whole argument for resolving it here: a contrast
/// rule applied at some of the call sites is a rule that is wrong at the rest.
///
/// **The dark room does not move.** On its ground the four tones measure
/// 12.2 (green), 12.0 (amber), 8.6 (red) and 10.1:1 (blue), and still 5.5:1 or
/// more on the menu step under a 16% wash, so the walk returns them untouched.
/// Only paper walks, and only where a ground or a wash takes a tone under the
/// bar.
///
/// [surface] is the ground the tone will be drawn on, defaulting to
/// [ColorScheme.surface]. Pass the real one when the tone lands on an elevated
/// container: on paper the day room's green measures 4.45:1 on
/// `surfaceContainerHighest`, and only the caller knows it is there.
///
/// [tintAlpha] is for the common badge shape where the tone is *both* the wash
/// behind the label and the label itself — a score pill on its own colour at
/// 16%, a filter chip on its own colour at 13%. The real ground there is the
/// composite, not the surface, and measuring against the surface alone passes
/// combinations that fail on screen: the day room's green on paper measures
/// 4.91:1 bare and 3.94:1 on its own 16% wash. Pair it with [statusToneFill],
/// which keeps the raw byte for the wash.
///
/// One tone is deliberately not walked: [StatusTone.neutral] resolves to
/// `onSurfaceVariant`, which is already a measured text token of the scheme and
/// is spaced against the worst surface the theme paints text on.
///
/// [StatusTone.primary] **is** walked, and used not to be. The argument for
/// exempting it was that walking the brand would quietly repaint it — true of
/// brand *chrome*, and not true here. This function does not colour buttons or
/// marks; it colours a status word, and a status word owes the same legibility
/// as every other status word beside it. In the monochrome room the primary
/// is the ink itself and passes everywhere, so the walk returns it untouched;
/// it stays in the walk so that a primary that is ever a hue again cannot ship
/// an unreadable status word. Chrome keeps `colorScheme.primary` directly and
/// is untouched by this.
Color statusToneColor(
  ColorScheme colorScheme,
  StatusTone tone, {
  Color? surface,
  double tintAlpha = 0,
}) {
  final ground = surface ?? colorScheme.surface;
  Color walked(Color tone) =>
      ServiceTheme.onTint(tone, surface: ground, tintAlpha: tintAlpha);

  final room = CupolaRoom.forBrightness(colorScheme.brightness);
  return switch (tone) {
    StatusTone.primary => walked(colorScheme.primary),
    StatusTone.success => walked(room.toneGreen),
    StatusTone.warning => walked(room.toneAmber),
    StatusTone.info => walked(room.toneBlue),
    StatusTone.error => walked(colorScheme.error),
    StatusTone.neutral => colorScheme.onSurfaceVariant,
  };
}

/// The tone's **fill** byte, unwalked.
///
/// The other half of [statusToneColor], and the distinction is the whole reason
/// the walk is safe to apply everywhere else: a fill is a surface, not a
/// foreground, and it carries no contrast obligation of its own — what it owes
/// is measured *by whatever is drawn on top of it*. Walking a fill would drag
/// every tinted wash in the app toward the ink and drain the colour out of the
/// one thing that is supposed to be coloured.
///
/// So: `statusToneFill` for the 10–16% wash behind a badge or a row, and
/// [statusToneColor] with the matching `tintAlpha` for the label on it.
///
/// [StatusTone.neutral] and [StatusTone.primary] are scheme roles in both
/// directions, so they answer the same here as they do there.
Color statusToneFill(ColorScheme colorScheme, StatusTone tone) {
  final room = CupolaRoom.forBrightness(colorScheme.brightness);
  return switch (tone) {
    StatusTone.primary => colorScheme.primary,
    StatusTone.success => room.toneGreen,
    StatusTone.warning => room.toneAmber,
    StatusTone.info => room.toneBlue,
    StatusTone.error => colorScheme.error,
    StatusTone.neutral => colorScheme.onSurfaceVariant,
  };
}

/// Maps a resolved status onto its icon.
///
/// Lives with the badge rather than on [MediaStatusInfo] so the status
/// vocabulary stays pure Dart.
IconData statusIconFor(MediaStatusInfo info) {
  final pipeline = info.pipeline;
  if (pipeline != null) {
    return switch (pipeline) {
      MediaPipeline.queued => Icons.schedule_rounded,
      MediaPipeline.downloading => Icons.downloading_rounded,
      // A transfer that should be moving and is not — distinct from a pause,
      // which the user chose.
      MediaPipeline.stalled => Icons.sync_problem_rounded,
      MediaPipeline.importPending => Icons.hourglass_bottom_rounded,
      MediaPipeline.importBlocked => Icons.block_rounded,
      MediaPipeline.importing => Icons.drive_file_move_rounded,
      MediaPipeline.paused => Icons.pause_circle_rounded,
      // `cloud_off` already means "this service did not answer" elsewhere in the
      // app (the Activity health strip and service tiles); an unreachable
      // download client is the same fact one layer down.
      MediaPipeline.clientUnavailable => Icons.cloud_off_rounded,
      MediaPipeline.failed => Icons.error_rounded,
    };
  }

  if (info.unmonitored && !info.isAvailable) {
    return Icons.bookmark_border_rounded;
  }

  // A status can describe an *event* rather than a thing on disk — a history
  // record, a blocked release — in which case it carries no availability and no
  // pipeline. Falling through to the availability switch gave all of those the
  // `unknown` question mark, which is the one glyph that tells the user
  // nothing.
  //
  // The resolver says what happened, and that is read first. It used to be
  // derived from the tone instead, which held only while every event that
  // needed its own picture also had its own colour — and stopped holding the
  // moment `Grabbed`, `Deleted` and `Blocked` became correctly neutral, because
  // one tone cannot answer for five different events.
  final glyph = info.glyph;
  if (glyph != null) {
    return switch (glyph) {
      StatusGlyph.grabbed => Icons.download_rounded,
      StatusGlyph.imported => Icons.check_circle_rounded,
      StatusGlyph.failed => Icons.warning_amber_rounded,
      StatusGlyph.ignored => Icons.do_not_disturb_on_rounded,
      StatusGlyph.deleted => Icons.delete_rounded,
      StatusGlyph.renamed => Icons.drive_file_rename_outline_rounded,
      StatusGlyph.blocked => Icons.block_rounded,
    };
  }

  if (info.availability == MediaAvailability.unknown && info.pipeline == null) {
    return switch (info.tone) {
      StatusTone.error => Icons.error_rounded,
      StatusTone.warning => Icons.warning_amber_rounded,
      StatusTone.success => Icons.check_circle_rounded,
      StatusTone.info => Icons.info_rounded,
      StatusTone.primary => Icons.add_circle_rounded,
      StatusTone.neutral => Icons.help_outline_rounded,
    };
  }

  return switch (info.availability) {
    MediaAvailability.notTracked => Icons.add_circle_rounded,
    MediaAvailability.available => Icons.check_circle_rounded,
    MediaAvailability.upgradable => Icons.upgrade_rounded,
    MediaAvailability.partial => Icons.donut_large_rounded,
    MediaAvailability.missing => Icons.cancel_rounded,
    MediaAvailability.unavailable => Icons.event_rounded,
    MediaAvailability.deleted => Icons.delete_rounded,
    MediaAvailability.unknown => Icons.help_outline_rounded,
  };
}
