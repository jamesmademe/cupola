import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// Semantic tone of a release row.
///
/// Drives the status rail, the grab button and the header badge so a list of
/// releases can be triaged at a glance: green = the \*Arr will accept it,
/// blue = it has reservations, amber = it refuses.
///
/// It used to carry its own `Color` and its own red, which made it a second
/// tone vocabulary beside [StatusTone] — and put the alarm colour on a screen
/// where nothing is unreachable. A release the decision engine refused is the
/// engine working: the \*Arr read the release, applied the profile and said no.
/// That is a fault of the release, not of the connection, and the three states
/// keep their ordering as green < blue < amber without borrowing red.
enum ReleaseStatusTone {
  approved(StatusTone.success, 'Approved'),
  pending(StatusTone.info, 'Not approved'),
  rejected(StatusTone.warning, 'Rejected');

  final StatusTone tone;
  final String label;
  const ReleaseStatusTone(this.tone, this.label);

  /// The painted colour, walked against [colorScheme]'s surface.
  Color color(ColorScheme colorScheme) => statusToneColor(colorScheme, tone);
}

/// The ground every label, chip and glyph inside a release row is measured
/// against: the row's own card, which [ReleaseListItem] fills with
/// `surfaceContainerHigh`. Measuring against the scaffold instead passes inks
/// that fail on the card in dark theme, where the card is the lighter of the
/// two.
Color _releaseRowGround(ColorScheme colorScheme) =>
    colorScheme.surfaceContainerHigh;

/// Resolves the [ReleaseStatusTone] for a raw release map.
///
/// Shares [releaseIsApproved] with the filter chip and the summary count so all
/// three agree on what "approved" means.
ReleaseStatusTone releaseStatusTone(dynamic release) {
  if (releaseIsRejected(release)) return ReleaseStatusTone.rejected;
  if (releaseIsApproved(release)) return ReleaseStatusTone.approved;
  return ReleaseStatusTone.pending;
}

/// A single release row in the Interactive Search sheet.
///
/// Collapsed, the row reads top-down: quality + protocol + custom-format score,
/// then the release title, then a metadata line (size, age, indexer, peers).
/// Tapping anywhere expands it to reveal the full title (with copy), the custom
/// formats breakdown and any rejection reasons.
class ReleaseListItem extends StatefulWidget {
  final dynamic release;

  /// Null while another row's grab is in flight, which disables this row's grab
  /// affordance so only one download can be started at a time.
  final VoidCallback? onGrab;

  /// Shows a spinner in place of the grab affordance while *this* row's grab is
  /// in flight, and blocks repeated taps.
  final bool isGrabbing;

  const ReleaseListItem({
    super.key,
    required this.release,
    required this.onGrab,
    this.isGrabbing = false,
  });

  @override
  State<ReleaseListItem> createState() => _ReleaseListItemState();
}

class _ReleaseListItemState extends State<ReleaseListItem> {
  bool _expanded = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final release = widget.release;

    final tone = releaseStatusTone(release);
    final releaseTitle = release['title'] as String? ?? 'Unknown';
    final indexer = release['indexer'] as String? ?? 'Unknown';
    final sizeStr = formatReleaseSize((release['size'] as num? ?? 0).toInt());
    final seeders = (release['seeders'] as num?)?.toInt();
    final leechers = (release['leechers'] as num?)?.toInt();
    final quality = release['quality']?['quality']?['name'] as String? ?? '';
    final ageStr = formatReleaseAge(
      (release['ageMinutes'] as num? ?? 0).toInt(),
    );
    final protocol = releaseProtocolOf(release);
    final score = (release['customFormatScore'] as num?)?.toInt() ?? 0;

    // One sentence for the row, its badges and meta silenced: it was read
    // pill by pill, a quality, a protocol and a score with no title to hang
    // them on. Grab stays its own control.
    final facts = [
      if (quality.isNotEmpty) quality,
      ?protocol?.label,
      sizeStr,
      ageStr,
      indexer,
      if (protocol == ReleaseProtocol.torrent && seeders != null)
        '$seeders seeders',
      if (score != 0) 'score ${score > 0 ? '+' : ''}$score',
    ].join(', ');
    final spoken = '$releaseTitle. $facts. ${tone.label}.';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _releaseRowGround(colorScheme),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(
            color: tone == ReleaseStatusTone.rejected
                ? tone.color(colorScheme).withValues(alpha: 0.28)
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: AppElevation.level1(colorScheme),
        ),
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusMd,
          child: Stack(
            children: [
              // Status rail — the fastest signal in the list.
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                width: 3,
                child: ColoredBox(
                  color: tone.color(colorScheme).withValues(alpha: 0.9),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: _toggle,
                  excludeFromSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Semantics(
                                container: true,
                                button: true,
                                label: spoken,
                                hint: _expanded
                                    ? 'Hide details'
                                    : 'Show details',
                                onTap: _toggle,
                                child: ExcludeSemantics(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _ReleaseBadgeRow(
                                        quality: quality,
                                        protocol: protocol,
                                        score: score,
                                        tone: tone,
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      Text(
                                        releaseTitle,
                                        maxLines: _expanded ? 4 : 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium!
                                            .weight(FontWeight.w600)
                                            .copyWith(height: 1.25),
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      _ReleaseMetaRow(
                                        indexer: indexer,
                                        sizeStr: sizeStr,
                                        ageStr: ageStr,
                                        seeders: seeders,
                                        leechers: leechers,
                                        isTorrent:
                                            protocol == ReleaseProtocol.torrent,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Column(
                              children: [
                                _GrabButton(
                                  tone: tone,
                                  busy: widget.isGrabbing,
                                  onPressed: widget.onGrab,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                AnimatedRotation(
                                  turns: _expanded ? 0.5 : 0,
                                  duration: AppAnimation.durationSm,
                                  curve: AppAnimation.standardCurve,
                                  child: Icon(
                                    Icons.expand_more_rounded,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        AnimatedSize(
                          duration: AppAnimation.durationSm,
                          curve: AppAnimation.standardCurve,
                          alignment: Alignment.topCenter,
                          child: _expanded
                              ? _ReleaseDetails(
                                  release: release,
                                  releaseTitle: releaseTitle,
                                  tone: tone,
                                  score: score,
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quality / protocol / custom-format score badges above the release title.
class _ReleaseBadgeRow extends StatelessWidget {
  final String quality;
  final ReleaseProtocol? protocol;
  final int score;
  final ReleaseStatusTone tone;

  const _ReleaseBadgeRow({
    required this.quality,
    required this.protocol,
    required this.score,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Badges wrap onto a second run instead of overflowing: quality names and
    // protocol labels vary a lot in width, and the score badge must stay put.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (quality.isNotEmpty)
                _Pill(
                  label: quality,
                  color: colorScheme.primary,
                  emphasize: true,
                ),
              if (protocol != null)
                _Pill(
                  label: protocol!.label,
                  icon: protocol!.icon,
                  color: colorScheme.onSurfaceVariant,
                ),
              if (tone == ReleaseStatusTone.rejected)
                _Pill(
                  label: tone.label,
                  icon: Icons.block_rounded,
                  color: statusToneFill(colorScheme, tone.tone),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        ScoreBadge(score: score),
      ],
    );
  }
}

/// Metadata line under the release title.
class _ReleaseMetaRow extends StatelessWidget {
  final String indexer;
  final String sizeStr;
  final String ageStr;
  final int? seeders;
  final int? leechers;
  final bool isTorrent;

  const _ReleaseMetaRow({
    required this.indexer,
    required this.sizeStr,
    required this.ageStr,
    required this.seeders,
    required this.leechers,
    required this.isTorrent,
  });

  @override
  Widget build(BuildContext context) {
    final peerColor = _peerColor(context);

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        InfoChip(icon: Icons.storage_outlined, text: sizeStr),
        InfoChip(icon: Icons.schedule_outlined, text: ageStr),
        InfoChip(icon: Icons.dns_outlined, text: indexer),
        if (seeders != null)
          InfoChip(
            icon: Icons.arrow_upward_rounded,
            text: leechers != null && isTorrent
                ? '$seeders / $leechers'
                : '$seeders',
            color: peerColor,
          ),
      ],
    );
  }

  /// Torrents with no seeders will never finish — call that out in colour.
  ///
  /// Amber rather than red: a swarm with nobody in it is a property of the
  /// release, and the indexer answered perfectly well to tell us so.
  Color? _peerColor(BuildContext context) {
    if (!isTorrent || seeders == null) return null;
    final colorScheme = Theme.of(context).colorScheme;
    final ground = _releaseRowGround(colorScheme);
    final tone = switch (seeders!) {
      0 => StatusTone.warning,
      < 5 => StatusTone.info,
      _ => StatusTone.success,
    };
    return statusToneColor(colorScheme, tone, surface: ground);
  }
}

/// Expanded content: full title, custom formats and rejection reasons.
class _ReleaseDetails extends StatelessWidget {
  final dynamic release;
  final String releaseTitle;
  final ReleaseStatusTone tone;
  final int score;

  const _ReleaseDetails({
    required this.release,
    required this.releaseTitle,
    required this.tone,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final customFormats =
        release['customFormats'] as List<dynamic>? ?? const [];
    final rejections = releaseRejectionReasons(release);
    // Neutral, not red. Red is reserved for a service that did not answer, and
    // a rejection reason is the opposite: the *Arr read the release, applied
    // the profile and said why not. The row already carries the refusal in
    // amber on its rail, pill and grab button; the reasons are the explanation
    // under it, so they read as text, with a `block` glyph so the list is not
    // told apart by colour alone.
    final rejectionInk = statusToneColor(colorScheme, StatusTone.neutral);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Divider(
          height: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: AppSpacing.md),

        // Full, untruncated release name with a copy affordance.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                releaseTitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 16),
              // No `VisualDensity.compact`: it takes 8 off the padded tap
              // target as well as the padding, so this measured 40 on a phone.
              tooltip: 'Copy release name',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: releaseTitle));
                if (context.mounted) {
                  SnackBarHelper.info(context, 'Copied');
                }
              },
            ),
          ],
        ),

        if (customFormats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _SectionHeader(title: 'Custom formats', score: score),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: customFormats.map<Widget>((cf) {
              return CustomFormatChip(
                name: cf['name'] as String? ?? 'Unknown',
                score: (cf['score'] as num?)?.toInt() ?? 0,
              );
            }).toList(),
          ),
        ],

        if (rejections.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const _SectionHeader(title: 'Rejection reasons'),
          const SizedBox(height: AppSpacing.xs),
          ...rejections.map(
            (reason) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.block_rounded,
                      size: 14,
                      color: rejectionInk,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      reason,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: rejectionInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        if (customFormats.isEmpty && rejections.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No custom format data available',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Circular grab affordance with an inline busy state.
class _GrabButton extends StatelessWidget {
  final ReleaseStatusTone tone;
  final bool busy;

  /// Null while any grab is in flight, which renders the button disabled.
  final VoidCallback? onPressed;

  const _GrabButton({
    required this.tone,
    required this.busy,
    required this.onPressed,
  });

  static const double _tintAlpha = 0.14;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The slot is the 48dp tap target (Android's floor, above iOS's 44pt);
    // the disc inside it stays 40. A tight 40 box used to clamp the target to
    // the disc, and `Center` is what lets the button pad itself back out.
    //
    // The glyph is a label on its own 14% wash over the card, so it is walked
    // against that composite; the wash keeps the tone's own byte.
    final ink = statusToneColor(
      colorScheme,
      tone.tone,
      surface: _releaseRowGround(colorScheme),
      tintAlpha: _tintAlpha,
    );
    final fill = statusToneFill(colorScheme, tone.tone);
    return SizedBox.square(
      dimension: kMinInteractiveDimension,
      child: busy
          ? Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: ink),
              ),
            )
          : Center(
              child: IconButton(
                icon: const Icon(Icons.download_rounded, size: 20),
                color: ink,
                onPressed: onPressed,
                tooltip: onPressed == null
                    ? 'Another download is starting'
                    : 'Grab release',
                style: IconButton.styleFrom(
                  backgroundColor: fill.withValues(
                    alpha: onPressed == null ? 0.06 : _tintAlpha,
                  ),
                  shape: const CircleBorder(),
                ),
              ),
            ),
    );
  }
}

/// Section label inside the expanded details, with an optional score badge.
class _SectionHeader extends StatelessWidget {
  final String title;
  final int? score;

  const _SectionHeader({required this.title, this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Text(
          title,
          // Not `AppTheme.eyebrow`: this repeats inside every expanded release
          // card (and twice in one when a release is both scored and
          // rejected), so it is a dense label, not a region kicker — and
          // therefore sentence case, since the eyebrow is the one uppercase
          // voice.
          style: theme.textTheme.labelSmall!
              .weight(FontWeight.w600)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (score != null) ...[
          const Spacer(),
          _Pill(
            label: 'Score: ${_signed(score!)}',
            color: statusToneFill(colorScheme, scoreTone(score!)),
          ),
        ],
      ],
    );
  }
}

/// The tone of a custom-format score: green when the profile rewards it,
/// neutral when it penalises it.
///
/// Not red. A negative score is the quality profile doing its job — the *Arr
/// weighed the format and marked it down — and red is reserved for a service
/// that did not answer. The minus sign carries the direction in words, so the
/// colour is not the only signal. Zero counts as positive, which is how the
/// chips always read it.
StatusTone scoreTone(int score) =>
    score >= 0 ? StatusTone.success : StatusTone.neutral;

/// Custom-format score badge shown on the right of the badge row.
class ScoreBadge extends StatelessWidget {
  final int score;

  const ScoreBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = score == 0 ? StatusTone.neutral : scoreTone(score);
    final tintAlpha = tone == StatusTone.neutral ? 0.10 : 0.16;

    // Fill and ink are different tokens, and this badge is the clearest case
    // for why: the wash keeps the tone's own byte so a positive score still
    // reads green, while the number on top of it is measured against the
    // composite it actually lands on. Painting both raw is what put a `+120` at
    // about 1.95:1 on paper — a green number on a green wash, legible at night
    // and effectively invisible in daylight.
    final fill = statusToneFill(colorScheme, tone);
    final ink = statusToneColor(
      colorScheme,
      tone,
      // These badges ride in release rows on a card, not on the scaffold.
      surface: _releaseRowGround(colorScheme),
      tintAlpha: tintAlpha,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: fill.withValues(alpha: tintAlpha),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _signed(score),
            // Scores stack down a release list and are read against each other.
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w600)
                .tabular
                .copyWith(color: ink),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            // Was fontSize 9; the unit keeps its dimmer tone to stay quieter
            // than the number it annotates. The 0.8 rides on an ink that has
            // already cleared AA, so the annotation lands just under the line
            // the way a caption is allowed to.
            'CF',
            style: theme.textTheme.labelSmall?.copyWith(
              color: ink.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip showing a custom format name with its score.
class CustomFormatChip extends StatelessWidget {
  final String name;
  final int score;

  const CustomFormatChip({super.key, required this.name, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tone = scoreTone(score);
    final color = statusToneFill(colorScheme, tone);
    // The wash keeps the tone's byte; the score is measured against it.
    final ink = statusToneColor(
      colorScheme,
      tone,
      surface: _releaseRowGround(colorScheme),
      tintAlpha: 0.12,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusFull,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _signed(score),
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w600)
                .tabular
                .copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

/// Small chip displaying an icon with text, used for metadata display.
class InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  /// Optional semantic tint (e.g. peer health). Defaults to the variant tone.
  final Color? color;

  const InfoChip({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: effective),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Every caller feeds this a size, an age or a seed/peer pair, and
            // the chips line up in a column down the release list.
            style: theme.textTheme.labelSmall!.tabular.copyWith(
              color: effective,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact tinted label used for quality, protocol and status.
///
/// [color] is the tone's byte and paints the wash; the label and glyph are that
/// tone walked against the wash over the row's card, so a quality pill in the
/// primary ink or a rejection in amber reads at AA in both themes.
class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;

  /// Carried by a denser tint, not by weight: the label is already at the 600
  /// ceiling for its role, and 700 on an 11px label read as shouting.
  final bool emphasize;

  const _Pill({
    required this.label,
    required this.color,
    this.icon,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tintAlpha = emphasize ? 0.16 : 0.10;
    final ink = ServiceTheme.onTint(
      color,
      surface: _releaseRowGround(theme.colorScheme),
      tintAlpha: tintAlpha,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: tintAlpha),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall!
                  .weight(FontWeight.w600)
                  .copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

String _signed(int score) => score >= 0 ? '+$score' : '$score';
