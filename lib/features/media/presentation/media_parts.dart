import 'package:flutter/material.dart';

import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart' show StatusBarScrim;
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/media/presentation/media_split.dart';

/// The room a title's page stands in: the ground washed with the title's
/// [light] (the lamp, unlit), the clock legible over whatever scrolls under
/// it, and beside a list the light coming up from the list's side rather
/// than starting at an edge.
class MediaRoom extends StatelessWidget {
  const MediaRoom({super.key, required this.light, required this.child});

  final TitleLight? light;

  /// The page.
  final Widget child;

  /// How far into a pane its title light takes to come up.
  static const double paneLightRise = 110;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ambient = BoxDecoration(
      gradient: AppGradients.ambientBackground(scheme, accent: light?.light),
    );
    final framed = Stack(
      children: [
        child,
        const Positioned(top: 0, left: 0, right: 0, child: StatusBarScrim()),
      ],
    );
    return Scaffold(
      backgroundColor: room.ground,
      body: MediaPane.maybeOf(context) == null
          ? DecoratedBox(decoration: ambient, child: framed)
          : Stack(
              fit: StackFit.expand,
              children: [
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: const [Color(0x00000000), Color(0xFF000000)],
                    stops: [0, (paneLightRise / bounds.width).clamp(0, 1)],
                  ).createShader(bounds),
                  child: DecoratedBox(decoration: ambient),
                ),
                framed,
              ],
            ),
    );
  }
}

/// One group of rows on a Media page or one of its sheets: the room's quiet
/// fill, `AppRadius.group`, a hairline round it and between the rows.
class MediaGroup extends StatelessWidget {
  const MediaGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.slabY),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.group),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) Divider(height: 1, color: room.hair),
            child,
          ],
        ],
      ),
    );
  }
}

/// The style of the one action that leads a Media page, and of the action
/// that closes one of its sheets: lit by the title, the tinted fill under its
/// ink in the dark room and the tinted primary under white in the day room.
/// Unlit, the ink.
///
/// A lead that only states something (`Requested`) stays legible: the
/// secondary ink on the room's strong fill, never Material's faded grey.
ButtonStyle mediaLeadStyle(BuildContext context, TitleLight? light) {
  final room = CupolaRoom.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  final primary = AppTheme.primaryButtonStyle(context);
  final fill = light == null
      ? primary.backgroundColor
      : WidgetStatePropertyAll<Color?>(
          dark ? light.actionFill : light.dayPrimary,
        );
  final ink = light == null
      ? primary.foregroundColor
      : WidgetStatePropertyAll<Color?>(
          dark ? light.actionInk : const Color(0xFFFFFFFF),
        );
  WidgetStateProperty<Color?> legible(
    WidgetStateProperty<Color?>? enabled,
    Color disabled,
  ) => WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? disabled
        : enabled?.resolve(states),
  );
  return primary.copyWith(
    backgroundColor: legible(fill, room.fillStrong),
    foregroundColor: legible(ink, room.inkSecondary),
    iconColor: legible(
      light == null ? primary.iconColor : ink,
      room.inkSecondary,
    ),
  );
}

/// A setting and its value, on the right; tapped to change it when there is
/// more than one to choose from.
class MediaValueRow extends StatelessWidget {
  const MediaValueRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final label = Text(
      this.label,
      style: AppType.row.copyWith(color: room.ink),
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            // At a large reading size the value goes under its label: side
            // by side, the label took the row and the value broke a letter
            // to a line.
            if (mediaStacked(context))
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, value],
                ),
              )
            else ...[
              label,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Align(alignment: Alignment.centerRight, child: value),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: room.inkTertiary,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// A setting that is on or off, with what that means under it.
class MediaSwitchRow extends StatelessWidget {
  const MediaSwitchRow({
    super.key,
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppType.row.copyWith(color: room.ink)),
                    Text(
                      detail,
                      style: AppType.meta
                          .weight(FontWeight.w400)
                          .copyWith(color: room.inkTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// A way somewhere else, with what it does under it: tapped whole, a
/// chevron at its end.
class MediaLinkRow extends StatelessWidget {
  const MediaLinkRow({
    super.key,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: AppType.row.copyWith(color: room.ink),
                        ),
                        Text(
                          detail,
                          style: AppType.meta
                              .weight(FontWeight.w400)
                              .copyWith(color: room.inkTertiary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: room.inkTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The back control: a 44 plate at rest over the room. In a tablet's pane it
/// goes back to the title opened before, or closes the pane.
class MediaBackPlate extends StatelessWidget {
  const MediaBackPlate({super.key});

  @override
  Widget build(BuildContext context) {
    final pane = MediaPane.maybeOf(context);
    final closes = pane != null && !pane.canGoBack;
    final words = MaterialLocalizations.of(context);
    // Its own node: merged into the page's first row, it read as wide as
    // the page and a pointer aimed at its middle missed the plate.
    return MediaPlate(
      label: closes ? words.closeButtonTooltip : words.backButtonTooltip,
      icon: closes ? Icons.close_rounded : Icons.chevron_left_rounded,
      iconSize: closes ? 22 : 26,
      onTap: pane?.onBack ?? () => Navigator.of(context).maybePop(),
    );
  }
}

/// A 44 plate at rest over the room, with one glyph: the back control, and
/// the page's other actions (`more_horiz`).
class MediaPlate extends StatelessWidget {
  const MediaPlate({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.iconSize = 22,
  });

  /// What it does, for a screen reader: the glyph says nothing.
  final String label;
  final IconData icon;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    // Its own node: merged into the page's first row, it read as wide as
    // the page and a pointer aimed at its middle missed the plate.
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          width: DesignTokens.sizeTouch,
          height: DesignTokens.sizeTouch,
          decoration: BoxDecoration(
            color: room.fillControl,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: room.edge),
          ),
          child: Icon(icon, size: iconSize, color: room.ink),
        ),
      ),
    );
  }
}

/// Past 1.4 times the reading size the page stacks what sits side by side:
/// the answer `SectionHeader` gives at the same threshold.
bool mediaStacked(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;

/// A section's heading on a Media page, and what it holds on the right
/// (`3 albums`).
class MediaHeading extends StatelessWidget {
  const MediaHeading(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.section,
        bottom: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
        ],
      ),
    );
  }
}

/// A state's word after its 7 dot, in its tone; the backlog's ring when
/// [hollow].
class MediaStateWord extends StatelessWidget {
  const MediaStateWord(
    this.word, {
    super.key,
    required this.tone,
    required this.hollow,
  });

  final String word;
  final StatusTone tone;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = statusToneColor(scheme, tone, surface: room.ground);
    // The info tone colours its word too, as the rows do with a download.
    final ink = tone == StatusTone.info || tone == StatusTone.warning
        ? color
        : room.inkSecondary;
    final style = AppType.meta.weight(FontWeight.w600).copyWith(color: ink);
    // The dot sits on the first line: a word that wraps keeps it there rather
    // than between its lines.
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        (style.height ?? 1.3);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: line,
          child: Center(
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hollow ? null : color,
                border: hollow
                    ? Border.all(color: room.inkSecondary, width: 1.5)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Flexible(child: Text(word, style: style)),
      ],
    );
  }
}
