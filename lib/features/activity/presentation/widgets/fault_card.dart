import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// A quieter way out on a fault's card: `Remove`, `Keep waiting`.
typedef FaultCardAction = ({
  String label,
  VoidCallback onPressed,
  String? semanticLabel,
});

/// What a card says once a way out was taken, in place of its controls:
/// `Dropped · Radarr is looking for another download`, with Undo where the
/// way out can be taken back.
typedef FaultCardNote = ({String text, VoidCallback? onUndo});

/// Work the remedy started and that is still running, in place of the fill:
/// `Scrubbing tank · 2% · about 9 h left`, and how far it got.
typedef FaultCardRunning = ({String text, double? progress});

/// One fault in Needs you, with its way out on the card.
///
/// A headline that is a sentence (`Big Buck Bunny is stuck at 47%`) by an
/// amber warning glyph, what it means, the service that raised it, and,
/// behind Why?, the service's own words. A download shows its proof: the
/// release in mono, how long nothing has arrived and which way its bytes
/// travel, and how far it got in amber.
///
/// Then the remedy: [primary] is the one amber fill (a fault's remedy is),
/// [primarySubtitle] says under it what it will do, and the quieter ways out
/// sit beside each other under that. Once one was taken the card says what
/// happened ([note]) in their place.
///
/// [FaultCard.whole] is the Needs you page's: a slab of its own, the headline
/// set larger and Why? already open.
class FaultCard extends StatefulWidget {
  const FaultCard({
    super.key,
    required this.headline,
    this.source,
    this.explanation,
    this.why,
    this.art,
    this.release,
    this.proof,
    this.progress,
    this.evidence = const [],
    this.primary,
    this.primarySubtitle,
    this.running,
    this.secondary = const [],
    this.note,
    this.divided = false,
  }) : _whole = false;

  const FaultCard.whole({
    super.key,
    required this.headline,
    this.source,
    this.explanation,
    this.why,
    this.art,
    this.release,
    this.proof,
    this.progress,
    this.evidence = const [],
    this.primary,
    this.primarySubtitle,
    this.running,
    this.secondary = const [],
    this.note,
  }) : divided = false,
       _whole = true;

  /// `Big Buck Bunny is stuck at 47%`.
  final String headline;

  /// The sentence under it: `Nothing has arrived for 3 hours, and nobody
  /// sharing it has the whole file any more.`
  final String? explanation;

  /// Who raised it: `Radarr · qBittorrent`, `Sonarr · Cosmos Laundromat`.
  /// Null where the proof already says it (a download's route).
  final String? source;

  /// The service's own words, behind Why?.
  final String? why;

  /// The poster, or the service's glyph on a plate.
  final Widget? art;

  /// The release, in mono: `Big.Buck.Bunny.2008.1080p.BluRay`.
  final String? release;

  /// `Nothing for 3 h · Radarr → qBittorrent`.
  final String? proof;

  /// How far it got, 0 to 1, drawn in amber.
  final double? progress;

  /// Further facts, a line each, on the page: `Pool tank · Healthy · 72%`.
  final List<String> evidence;

  /// The amber fill.
  final Widget? primary;

  /// What [primary] does: `Radarr drops this one (1.1 GB so far), won't pick
  /// it again, and looks for another.`
  final String? primarySubtitle;

  /// Work under way, drawn in place of [primary]: blue, informational.
  final FaultCardRunning? running;

  /// The quieter ways out, at most two, beside each other.
  final List<FaultCardAction> secondary;

  /// Said in place of the controls once a way out was taken.
  final FaultCardNote? note;

  /// Whether a hairline separates it from the card above, inside a slab.
  final bool divided;

  final bool _whole;

  @override
  State<FaultCard> createState() => _FaultCardState();
}

class _FaultCardState extends State<FaultCard> {
  late bool _whyOpen = widget._whole;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final amber = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: room.slab,
    );
    final card = widget;
    final why = card.why;
    final note = card.note;
    final headlineStyle = (card._whole ? AppType.section : AppType.row)
        .copyWith(color: room.ink);

    final facts = Semantics(
      container: true,
      label: [
        card.headline,
        ?card.explanation,
        ?card.source,
        ?card.release,
        ?card.proof,
        ...card.evidence,
      ].join('. '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.warning_rounded,
                  size: card._whole ? 20 : 16,
                  color: amber,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(card.headline, style: headlineStyle)),
            ],
          ),
          if (card.explanation case final explanation?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              explanation,
              style: AppType.body.copyWith(color: room.inkSecondary),
            ),
          ],
          if (card.source case final source?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(source, style: AppType.meta.copyWith(color: room.inkTertiary)),
          ],
          if (card.release case final release?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              release,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: AppType.mono.copyWith(color: room.inkSecondary),
            ),
          ],
          if (card.proof case final proof?) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(proof, style: AppType.meta.copyWith(color: room.inkSecondary)),
          ],
          for (final line in card.evidence) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(line, style: AppType.meta.copyWith(color: room.inkSecondary)),
          ],
          if (card.progress case final progress?) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1).toDouble(),
                minHeight: 4,
                color: amber,
                backgroundColor: room.fillTrack,
              ),
            ),
          ],
        ],
      ),
    );

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.art case final art?) ...[
          art,
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              facts,
              if (why != null) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _whyOpen = !_whyOpen),
                    iconAlignment: IconAlignment.end,
                    style: TextButton.styleFrom(
                      foregroundColor: room.inkSecondary,
                      minimumSize: const Size(44, 44),
                      visualDensity: VisualDensity.standard,
                      padding: EdgeInsets.zero,
                    ),
                    icon: Icon(
                      _whyOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                    ),
                    label: Text(
                      'Why?',
                      semanticsLabel: _whyOpen ? 'Hide why' : 'Why?',
                    ),
                  ),
                ),
                if (_whyOpen)
                  Text(
                    why,
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
              ],
            ],
          ),
        ),
      ],
    );

    final controls = note != null
        ? _Note(note: note)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (card.running case final running?)
                _Running(running: running)
              else
                ?card.primary,
              if (card.primarySubtitle case final subtitle?
                  when card.running == null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
              ],
              if (card.secondary.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    for (final (index, action) in card.secondary.indexed) ...[
                      if (index > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: action.onPressed,
                          child: Text(
                            action.label,
                            semanticsLabel: action.semanticLabel,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          );

    final content = Padding(
      padding: EdgeInsets.symmetric(
        vertical: card._whole ? AppSpacing.lg : AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          const SizedBox(height: AppSpacing.md),
          controls,
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: card.divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: content,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.note});

  final FaultCardNote note;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final undo = note.onUndo;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                note.text,
                style: AppType.label.copyWith(color: room.inkSecondary),
              ),
            ),
          ),
          if (undo != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: undo,
              style: TextButton.styleFrom(
                foregroundColor: room.ink,
                minimumSize: const Size(56, 44),
                visualDensity: VisualDensity.standard,
              ),
              child: const Text('Undo'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.running});

  final FaultCardRunning running;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final blue = statusToneColor(
      Theme.of(context).colorScheme,
      StatusTone.info,
      surface: room.slab,
    );
    final progress = running.progress;
    return Semantics(
      liveRegion: true,
      label: running.text,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(running.text, style: AppType.label.copyWith(color: blue)),
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.clamp(0, 1).toDouble(),
                  minHeight: 4,
                  color: blue,
                  backgroundColor: room.fillTrack,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
