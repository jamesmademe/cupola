/// The parts the Home's modules share inside their slab: the way on to the
/// page behind a module, the line that names a source that did not answer,
/// the art beside a row and the bar under it.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';

/// The way from a module to the page behind it: `See all in Activity`.
class HomeModuleLink extends StatelessWidget {
  const HomeModuleLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusSm,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta
                      .weight(FontWeight.w600)
                      .copyWith(color: room.inkSecondary),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: room.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The line over a module's rows that names the sources it reads without:
/// red when one did not answer, amber when one refused.
///
/// Silent to a screen reader: the module's own label already says it.
class HomeCoverageNote extends StatelessWidget {
  const HomeCoverageNote({
    super.key,
    required this.note,
    required this.coverage,
  });

  final String note;
  final SourceCoverage coverage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ExcludeSemantics(
        child: coverage.anyDidNotAnswer
            ? FaultNote.unreachable(message: note)
            : FaultNote.fault(message: note),
      ),
    );
  }
}

/// The 36×54 art beside a module's row: the title's poster, or the plate of
/// the service it came from when there is none.
class HomeRowArt extends StatelessWidget {
  const HomeRowArt({super.key, required this.posterUrl, required this.icon});

  final String? posterUrl;
  final IconData icon;

  static const width = 36.0;
  static const height = 54.0;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl;
    final room = CupolaRoom.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: url == null || url.isEmpty
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: room.fillQuiet,
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Icon(icon, size: 18, color: room.inkSecondary),
            )
          : ContentCard(imageUrl: url),
    );
  }
}

/// The 4pt bar under a row: how far it got, in [color] over the track.
class HomeRowBar extends StatelessWidget {
  const HomeRowBar({super.key, required this.value, required this.color});

  /// 0 to 1.
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: LinearProgressIndicator(
          value: value.clamp(0, 1).toDouble(),
          minHeight: 4,
          color: color,
          backgroundColor: CupolaRoom.of(context).fillTrack,
        ),
      ),
    );
  }
}
