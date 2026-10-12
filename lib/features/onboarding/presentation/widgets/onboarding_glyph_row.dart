import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The ring resolved into a result: the services that answered, each as its own
/// lit glyph tile.
///
/// The close is the one beat where the ring has finished saying what it had to
/// say (every node is settled), so the instrument hands over to a row that
/// names the outcome instead of tracking it. Tiles rather than the ring's dots
/// because this is the only place in the flow where the answer is a *list of
/// services* rather than a proportion of them.
///
/// The wrap is bounded, not endless: [maxTiles] tiles across at most two rows,
/// then one `+N` pill. A third row of glyphs stops being a result and starts
/// being an inventory, and on the narrowest frame: 17 services picked and all
/// of them answering, which is the case the phone board is drawn at. That is
/// exactly what it became.
class OnboardingGlyphRow extends StatelessWidget {
  const OnboardingGlyphRow({super.key, required this.services});

  final List<ServiceKey> services;

  /// Twelve drawn, the rest counted. Two rows of six on the phone, which is
  /// what the drawn maximum case resolves to.
  static const maxTiles = 12;

  /// The tile at the size the desktop and compact boards draw it, and the size
  /// it falls to when the frame cannot hold the wrap in two rows.
  static const _fullTile = 42.0;
  static const _smallTile = 30.0;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) return const SizedBox.shrink();
    final drawn = services.take(maxTiles).toList(growable: false);
    final overflow = services.length - drawn.length;
    // The pill is a cell like any other: it wraps with the tiles rather than
    // being pinned to the end of the last row, so twelve tiles plus a `+5` is
    // 13 cells laid out as 7 and 6, not 12 and a widow.
    final cells = drawn.length + (overflow > 0 ? 1 : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size follows the fit, not the platform. The phone board draws 30pt
        // tiles and the two desktop boards draw 42pt ones, but the thing that
        // actually separates them is whether half the cells fit one line: at
        // 42pt seven tiles want 354pt and the phone's row is 344pt wide, so it
        // would have spilled onto a third row. Asking the question this way
        // also means a tablet or a dragged-narrow window answers it correctly
        // without a device check.
        final perRow = (cells / 2).ceil();
        final wanted = perRow * _fullTile + (perRow - 1) * AppSpacing.md;
        final fits =
            !constraints.maxWidth.isFinite || wanted <= constraints.maxWidth;
        final tile = fits ? _fullTile : _smallTile;
        // The gaps the boards draw (10 and 8) straddle a rung of the spacing
        // ladder; the row takes the ladder rather than carrying two numbers of
        // its own.
        final gap = fits ? AppSpacing.md : AppSpacing.sm;

        return Semantics(
          // One stop rather than thirteen: each tile is a glyph whose entire
          // meaning is the name under it, and a screen reader walking them one
          // by one reads the result as a menu. The count carries the services
          // the wrap dropped, which is the one thing the drawing cannot say.
          label: [
            drawn.map((s) => s.title).join(', '),
            if (overflow > 0) 'and $overflow more',
          ].join(', '),
          excludeSemantics: true,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final service in drawn)
                _GlyphTile(service: service, size: tile),
              if (overflow > 0) _OverflowPill(count: overflow, size: tile),
            ],
          ),
        );
      },
    );
  }
}

class _GlyphTile extends StatelessWidget {
  const _GlyphTile({required this.service, required this.size});

  final ServiceKey service;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Seven of the seventeen accents fall under 3:1 on paper, so the glyph is
    // never the raw accent: it is the ink `onTint` resolves for an accent
    // sitting on its own 16% wash.
    final ink = ServiceTheme.onTint(
      service.accent,
      surface: scheme.surface,
      tintAlpha: 0.16,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: service.accent.withValues(alpha: 0.16),
        // The boards draw 14; the radius ladder has 12 and 16 and this tile is
        // not worth a third rung, so it takes the nearer one.
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: service.accent.withValues(alpha: 0.5)),
        boxShadow: [
          // The lit part. A service that answered is the only thing in this
          // flow that gets to glow, and the glow is its own accent rather than
          // a neutral shadow. The row is a result, not a toolbar.
          BoxShadow(
            color: service.accent.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(service.icon, size: size * 0.43, color: ink),
    );
  }
}

class _OverflowPill extends StatelessWidget {
  const _OverflowPill({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: size,
      constraints: BoxConstraints(minWidth: size),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        // Neutral, and deliberately so: the pill counts services, it does not
        // stand for one, so borrowing any accent would make five services look
        // like a sixth one nobody can name.
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '+$count',
        // Tabular because it sits in a row of fixed-width cells and a
        // proportional `1` would shift the pill's width as the count changes.
        style: AppTheme.chrome(
          context,
          size: 11,
          weight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ).tabular,
      ),
    );
  }
}
