import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/status/media_action.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One row of the actions overflow sheet.
///
/// [MediaOverflowAction.destructive] is a separate constructor rather than a
/// flag because it changes where the row *lands*: the sheet sorts every
/// destructive action below a divider, last, furthest from where the thumb
/// arrives. Delete used to sit roughly ten points from Manual Import in an
/// undifferentiated `spaceAround` row, told apart by hue alone.
@immutable
class MediaOverflowAction {
  final String label;
  final IconData icon;

  /// Null disables the row. Kept rather than omitted when a host wants the
  /// action visible but unavailable; most callers simply omit it instead.
  final VoidCallback? onInvoke;

  final bool isDestructive;

  const MediaOverflowAction({
    required this.label,
    required this.icon,
    this.onInvoke,
  }) : isDestructive = false;

  const MediaOverflowAction.destructive({
    required this.label,
    required this.icon,
    this.onInvoke,
  }) : isDestructive = true;
}

/// A non-promoted action plus the rank at which it may claim a visible slot.
///
/// Two orders, one list. The sheet renders in list order; the row fills its
/// slots by [visibleRank]. Keeping both on one object is what makes it
/// impossible for an action to be shown twice or to disappear from both places.
@immutable
class _SecondaryCandidate {
  final MediaOverflowAction action;

  /// Lower wins a slot first. Null can never be visible.
  final int? visibleRank;

  // No `visibleLabel` override any more. It existed for exactly one candidate —
  // the quality profile, which said `Quality profile: HD-1080p` in the sheet and
  // `Quality profile` on the button — and that candidate left with decision 25.
  // Every remaining action is a verb that fits on a button as it is written.
  const _SecondaryCandidate({required this.action, required this.visibleRank});

  String get visibleName => action.label;
}

/// The candidates that earn the row's visible slots, in rank order.
///
/// Anything without a rank, or without an invoker, is filtered out first: a
/// visible control that does nothing is worse than one that was never offered,
/// and this band's whole rule is that an action is withheld rather than
/// disabled.
List<_SecondaryCandidate> _visibleSecondaries(
  List<_SecondaryCandidate> candidates, {
  required int slots,
}) {
  if (slots <= 0) return const [];
  final ranked =
      candidates
          .where(
            (candidate) =>
                candidate.visibleRank != null &&
                candidate.action.onInvoke != null,
          )
          .toList()
        ..sort((a, b) => a.visibleRank!.compareTo(b.visibleRank!));

  return ranked.take(slots).toList(growable: false);
}

/// Shows the non-promoted actions for a media detail page.
///
/// [title] is the media title, shown as the sheet's subtitle. [actions] are
/// rendered in the order given, with one exception the sheet enforces itself:
/// every [MediaOverflowAction.destructive] is moved below a divider at the
/// bottom, so a caller cannot accidentally seat Delete beside Import.
///
/// **Haptics live here, once.** Each service screen used to fire its own, and
/// they had drifted: Radarr fired `selectionClick` on both searches and
/// `mediumImpact` before Delete while Sonarr and Lidarr fired nothing at all.
/// The sheet is the tap target now, so the sheet owns the feedback — a
/// destructive row gets `mediumImpact`, everything else `selectionClick`, and
/// [PressableScale]'s own light impact is suppressed so exactly one fires.
Future<void> showMediaDetailActions(
  BuildContext context, {
  required Color accent,
  required String title,
  required List<MediaOverflowAction> actions,
}) {
  final safe = actions.where((action) => action.label.isNotEmpty).toList();

  return AppBottomSheet.show<void>(
    context: context,
    title: 'Actions',
    subtitle: title,
    icon: Icons.more_horiz_rounded,
    accent: accent,
    builder: (sheetContext) => _MediaOverflowRows(actions: safe),
  );
}

/// The sheet's rows, and the one thing they share: a sheet spends itself on a
/// single action.
///
/// The rows sit on a route that pops *before* the action runs, and a
/// [MediaOverflowAction] is a bare [VoidCallback] — so the host learns about a
/// tap only once it has already started the work, and cannot refuse a second
/// one. Two fingers landing on Manual import and Delete in the same frame is
/// enough: both rows fire, both pop, and the second pop takes the detail page
/// with it while a delete is already in flight. The guard belongs here, where
/// the sheet knows it has been used.
class _MediaOverflowRows extends StatefulWidget {
  final List<MediaOverflowAction> actions;

  const _MediaOverflowRows({required this.actions});

  @override
  State<_MediaOverflowRows> createState() => _MediaOverflowRowsState();
}

class _MediaOverflowRowsState extends State<_MediaOverflowRows> {
  bool _spent = false;

  void _invoke(MediaOverflowAction action) {
    if (_spent) return;
    setState(() => _spent = true);
    if (action.isDestructive) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    Navigator.of(context).pop();
    action.onInvoke!();
  }

  @override
  Widget build(BuildContext context) {
    final ordinary = widget.actions.where((action) => !action.isDestructive);
    final destructive = widget.actions.where((action) => action.isDestructive);

    Widget row(MediaOverflowAction action) => _MediaOverflowRow(
      action: action,
      onInvoke: action.onInvoke == null || _spent
          ? null
          : () => _invoke(action),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in ordinary) row(action),
        if (destructive.isNotEmpty && ordinary.isNotEmpty)
          Divider(
            height: AppSpacing.xl,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        for (final action in destructive) row(action),
      ],
    );
  }
}

class _MediaOverflowRow extends StatelessWidget {
  final MediaOverflowAction action;

  /// Null disables the row — either the action carries no invoker, or the sheet
  /// has already been spent on another one.
  final VoidCallback? onInvoke;

  const _MediaOverflowRow({required this.action, required this.onInvoke});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onInvoke != null;
    final glyphColor = enabled
        ? (action.isDestructive
              ? colorScheme.error
              : colorScheme.onSurfaceVariant)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    final labelColor = enabled
        ? (action.isDestructive ? colorScheme.error : colorScheme.onSurface)
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return PressableScale(
      // Exactly one haptic per row, fired below.
      haptic: false,
      semanticLabel: action.label,
      excludeChildSemantics: true,
      onTap: onInvoke,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HeaderActionRow.buttonHeight,
        ),
        child: Row(
          children: [
            Icon(
              action.icon,
              size: ActionStateGlyph.glyphSize,
              color: glyphColor,
            ),
            const SizedBox(width: AppSpacing.md),
            // A full-width labelled row cannot truncate, which is what retires
            // the 58pt captions that ellipsised to "Inter…" / "Auto…".
            Expanded(
              child: Text(
                action.label,
                style: theme.textTheme.bodyLarge!
                    .weight(FontWeight.w600)
                    .copyWith(color: labelColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status-led action band for the library detail screens (Radarr, Sonarr,
/// Lidarr).
///
/// **Never pad this widget.** The detail spine owns the gutter and every gap; a
/// caller that adds its own inset ships a visible mid-page jog.
///
/// One resolved status in, one promoted action out, everything else in an
/// overflow sheet. What this replaces was six controls of equal weight: a
/// full-width accent CTA reading "Unmonitor" on an *available* series, over five
/// 42pt circular buttons at `spaceAround` that mixed read-only actions
/// (Interactive, Auto Search, Profile) with a state change (Import) and a
/// destructive one (Delete) into one undifferentiated group — six simultaneous
/// choices at the top of the screen, in the least accurate part of the thumb's
/// reach, against a working-memory limit of about four.
class LibraryDetailActions extends StatelessWidget {
  /// The service that owns this page.
  ///
  /// One parameter rather than an accent plus a name, because the two must never
  /// disagree: the accent lights the promoted verb and the name appears in the
  /// consequence sentence.
  final ServiceKey service;

  /// The fully resolved status, from the feature's `domain/` layer.
  ///
  /// This widget derives no status. It promotes an action *from* one.
  final MediaStatusInfo status;

  /// The media title, used as the overflow sheet's subtitle.
  final String mediaTitle;

  /// Whether the user's copy is monitored. Wording of the overflow row only —
  /// monitoring is a persistent binary, not an action.
  final bool isMonitored;

  /// Human summary of a partial manifest, e.g. '41 of 48 episodes on disk.'
  final String? partialSummary;

  /// Replaces the consequence for a state the ladder cannot know on its own —
  /// a release date on a title that has not come out yet.
  final String? consequenceOverride;

  /// True while a write started from this band is in flight: the promoted
  /// action's glyph spins and **nothing in the band accepts a tap** — not the
  /// promoted button, not the visible secondaries, not the overflow trigger.
  ///
  /// One flag rather than one per action, because the band is one console for
  /// one item: whatever is in flight, a second command against the same title is
  /// never what the user meant. Map the host's own in-flight flags onto it —
  /// `_isAutoSearching || _isUpdatingMonitoredState || _isDeleting`.
  ///
  /// It is the *only* re-entrancy guard on this path. Hosts hand over bare
  /// [VoidCallback]s that fire a service command directly, so before this reached
  /// past the promoted button, triple-tapping the auto-search secondary sent
  /// three searches and the overflow could start a second Delete on top of a
  /// running one.
  final bool isBusy;

  /// Momentarily true after the promoted action lands; holds a success check in
  /// place of the glyph for [AppAnimation.confirmationHold].
  final bool isConfirmed;

  /// Automatic search. Null withholds both the promotion and the overflow row.
  final VoidCallback? onSearch;

  /// Interactive (release picker) search.
  final VoidCallback? onInteractiveSearch;

  /// Manual import.
  final VoidCallback? onImport;

  /// Route to the download queue. Null makes every in-flight state explain
  /// itself in a sentence rather than promote a button that goes nowhere.
  final VoidCallback? onOpenQueue;

  /// Sets the monitored flag. Receives the *desired* value.
  final ValueChanged<bool>? onMonitoredChanged;

  /// Deletes the item from the service. Always lands last in the overflow.
  final VoidCallback? onDelete;

  // No quality-profile fields, and that is decision 25 rather than an omission:
  // **a detail edits in place.** The profile is a field, it is read in the
  // Details grid, and it is now changed there through `MediaDetailValueRow`.
  // This band used to carry it twice over — `Quality profile: HD-1080p` in the
  // overflow *and* promoted into the visible row at `visibleRank: 1` — which put
  // a field edit among the verbs, offered one thing at two densities in two
  // places, and left the grid showing a value that looked untouchable.
  //
  // What stays here is whole-item only: search, interactive search, monitor,
  // manual import, delete.

  const LibraryDetailActions({
    super.key,
    required this.service,
    required this.status,
    required this.mediaTitle,
    this.isMonitored = false,
    this.partialSummary,
    this.consequenceOverride,
    this.isBusy = false,
    this.isConfirmed = false,
    this.onSearch,
    this.onInteractiveSearch,
    this.onImport,
    this.onOpenQueue,
    this.onMonitoredChanged,
    this.onDelete,
  });

  MediaActionCapabilities get _capabilities => MediaActionCapabilities(
    canSearch: onSearch != null,
    canInteractiveSearch: onInteractiveSearch != null,
    canImport: onImport != null,
    canMonitor: onMonitoredChanged != null,
    canOpenQueue: onOpenQueue != null,
  );

  /// The promoted action for this status. Exposed so a host (or a test) can read
  /// the same decision the band renders instead of re-deriving it.
  MediaPrimaryAction get promotedAction => resolveMediaAction(
    status,
    _capabilities,
    serviceName: service.title,
    partialSummary: partialSummary,
    consequenceOverride: consequenceOverride,
  );

  /// Every tap target in the band goes through here, so [isBusy] can never be
  /// honoured by one rung and forgotten by the next.
  VoidCallback? _whenIdle(VoidCallback? invoke) => isBusy ? null : invoke;

  VoidCallback? _invokerFor(MediaActionKind kind) {
    switch (kind) {
      case MediaActionKind.openQueue:
        return onOpenQueue;
      case MediaActionKind.search:
        return onSearch;
      case MediaActionKind.interactiveSearch:
        return onInteractiveSearch;
      case MediaActionKind.manualImport:
        return onImport;
      case MediaActionKind.monitor:
        final setter = onMonitoredChanged;
        return setter == null ? null : () => setter(true);
      case MediaActionKind.request:
      case MediaActionKind.add:
      case MediaActionKind.refresh:
      case MediaActionKind.none:
        return null;
    }
  }

  /// Everything the promoted action did *not* take, in one fixed order.
  ///
  /// The promoted kind is skipped, so the sheet holds exactly the non-promoted
  /// actions and the same verb never appears twice.
  /// Every non-promoted action, in *sheet* order, each carrying the rank at
  /// which it may claim one of the row's visible slots.
  ///
  /// The two orders are deliberately different. The sheet reads best grouped by
  /// kind — both searches together, then state, then the destructive one last.
  /// The row must never spend both of its slots on two searches, so
  /// `visibleRank` promotes Interactive search first. A null rank can only ever
  /// appear in the sheet, which is how Delete is kept from becoming a visible
  /// peer of Import on any rung.
  List<_SecondaryCandidate> _candidates(MediaActionKind promoted) {
    return <_SecondaryCandidate>[
      if (onInteractiveSearch != null &&
          promoted != MediaActionKind.interactiveSearch)
        _SecondaryCandidate(
          visibleRank: 0,
          action: MediaOverflowAction(
            label: 'Interactive search',
            icon: Icons.search_rounded,
            onInvoke: onInteractiveSearch,
          ),
        ),
      if (onSearch != null && promoted != MediaActionKind.search)
        _SecondaryCandidate(
          visibleRank: 2,
          action: MediaOverflowAction(
            label: 'Automatic search',
            icon: Icons.saved_search_rounded,
            onInvoke: onSearch,
          ),
        ),
      if (onMonitoredChanged != null && promoted != MediaActionKind.monitor)
        _SecondaryCandidate(
          visibleRank: 4,
          action: MediaOverflowAction(
            label: isMonitored ? 'Stop monitoring' : 'Monitor',
            icon: isMonitored
                ? Icons.bookmark_remove_outlined
                : Icons.bookmark_add_outlined,
            onInvoke: () => onMonitoredChanged!(!isMonitored),
          ),
        ),
      if (onImport != null && promoted != MediaActionKind.manualImport)
        _SecondaryCandidate(
          // Rank 1 is vacant, and stays vacant: it belonged to the quality
          // profile until decision 25 moved that field onto its own row in the
          // Details card. Closing the gap would re-order the band — Manual
          // import would start taking the single visible slot from Automatic
          // search on an upgradable title — and nothing in that decision asked
          // for the promotion order to change.
          visibleRank: 3,
          action: MediaOverflowAction(
            label: 'Manual import',
            icon: Icons.download_for_offline_outlined,
            onInvoke: onImport,
          ),
        ),
      if (onDelete != null)
        _SecondaryCandidate(
          // Never visible. A destructive action is not a peer of Import in a
          // row of identical discs, which is what the previous band shipped.
          visibleRank: null,
          action: MediaOverflowAction.destructive(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            onInvoke: onDelete,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = service.accent;
    // Never a local luminance threshold: `> 0.55 ? black : white` put white on
    // Radarr's amber at roughly 2.1:1 — on the loudest control of the page.
    final onAccent = ServiceTheme.foregroundOn(accent);

    final action = promotedAction;
    final invoker = _invokerFor(action.kind);
    final hasPrimary = action.kind != MediaActionKind.none && invoker != null;

    // A withheld primary frees both slots. That is the whole answer to a row
    // that read as an empty shelf on an available title: the promotion rule is
    // unchanged — promoting a search on a complete title is what the previous
    // pass deliberately killed — but the space it leaves is now spent on the two
    // actions an operator does reach for, instead of on nothing.
    final candidates = _candidates(action.kind);
    final visible = _visibleSecondaries(candidates, slots: hasPrimary ? 1 : 2);
    final overflow = candidates
        .where((candidate) => !visible.contains(candidate))
        .map((candidate) => candidate.action)
        .toList(growable: false);

    final consequence = Text(
      action.consequence,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall!.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );

    final tonalStyle = HeaderActionRow.tonalIconButtonStyle(
      foregroundColor: colorScheme.onSurfaceVariant,
      backgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
      borderColor: colorScheme.outlineVariant,
    );

    Widget? overflowDisc;
    if (overflow.isNotEmpty) {
      overflowDisc = SizedBox.square(
        dimension: HeaderActionRow.buttonHeight,
        child: OutlinedButton(
          onPressed: _whenIdle(
            () => showMediaDetailActions(
              context,
              accent: accent,
              title: mediaTitle,
              actions: overflow,
            ),
          ),
          style: tonalStyle,
          child: const Icon(
            Icons.more_horiz_rounded,
            size: ActionStateGlyph.glyphSize,
            semanticLabel: 'More actions',
          ),
        ),
      );
    }

    // Icon-only, for the rungs where a primary already holds the wide slot.
    // The glyph carries the accessible name because there is no visible caption
    // to read: a 9pt caption in a fixed box is exactly what ellipsised to
    // "Inter…" and "Auto…" in the band this replaced.
    Widget secondaryDisc(_SecondaryCandidate candidate) => SizedBox.square(
      dimension: HeaderActionRow.buttonHeight,
      child: OutlinedButton(
        // Disabled rather than withheld while the band is busy: a control that
        // vanishes mid-write reflows the row under the thumb, which is how the
        // next tap lands on whatever slid into its place.
        onPressed: _whenIdle(candidate.action.onInvoke),
        style: tonalStyle,
        child: Icon(
          candidate.action.icon,
          size: ActionStateGlyph.glyphSize,
          semanticLabel: candidate.visibleName,
        ),
      ),
    );

    // Labelled, for the rungs with no primary. Two bare discs beside a wide
    // empty gap read as leftovers; a labelled pair reads as a console. The label
    // is clamped and wraps to two lines rather than eliding, for the same reason
    // the primary's is.
    // **No glyph on this variant, and that is arithmetic rather than taste.**
    // Two buttons plus the overflow disc leave roughly 150pt each on a 402pt
    // phone, and an 18pt glyph, its 8pt gap and 12pt of padding either side eat
    // about 50 of that — leaving ~100pt for a label that wants 118. So
    // "Interactive search" wrapped to two centred lines beside a left-hanging
    // icon, which is exactly what it looked like: an accident. With only two
    // controls on a wide row the words *are* the affordance, so the glyph gives
    // its width back to them and stays on the icon-only variant, where it is the
    // whole control. The label still wraps rather than elides once a reading
    // size genuinely needs a second line.
    Widget secondaryButton(_SecondaryCandidate candidate) => OutlinedButton(
      onPressed: _whenIdle(candidate.action.onInvoke),
      style:
          HeaderActionRow.tonalExpandedButtonStyle(
            foregroundColor: colorScheme.onSurfaceVariant,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
            borderColor: colorScheme.outlineVariant,
          ).copyWith(
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
          ),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: Text(
          candidate.visibleName,
          maxLines: 2,
          textAlign: TextAlign.center,
        ),
      ),
    );

    final trailingChildren = <Widget>[
      if (hasPrimary) ...visible.map(secondaryDisc),
      ?overflowDisc,
    ];
    final trailing = trailingChildren.isEmpty
        ? null
        : trailingChildren.length == 1
        ? trailingChildren.single
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < trailingChildren.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                trailingChildren[i],
              ],
            ],
          );

    if (!hasPrimary) {
      if (visible.isEmpty) {
        // Nothing promoted and no capability to surface: the sentence takes the
        // wide slot so the band is never a lone overflow button with nothing to
        // explain it.
        return HeaderActionRow(expanded: consequence, trailing: trailing);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeaderActionRow(
            expanded: Row(
              children: <Widget>[
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: secondaryButton(visible[i])),
                ],
              ],
            ),
            trailing: trailing,
          ),
          if (action.consequence.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            consequence,
          ],
        ],
      );
    }

    // The label is clamped at 1.6x for the reason the stacking section header
    // is: Flutter's answer to a single word too wide for its line is to break it
    // mid-word, which is how the request button came to read "Requeste / d".
    Widget label = MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
      child: Text(
        action.label,
        key: ValueKey(action.label),
        maxLines: 2,
        textAlign: TextAlign.center,
      ),
    );
    if (!reduceMotion) {
      label = AnimatedSwitcher(
        duration: AppAnimation.durationSm,
        switchInCurve: AppAnimation.emphasizedCurve,
        child: label,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeaderActionRow(
          expanded: FilledButton.icon(
            onPressed: _whenIdle(invoker),
            icon: ActionStateGlyph(
              icon: action.icon,
              label: action.label,
              isBusy: isBusy,
              isConfirmed: isConfirmed,
              color: onAccent,
              fill: accent,
            ),
            label: label,
            style: HeaderActionRow.expandedButtonStyle(
              foregroundColor: onAccent,
              backgroundColor: accent,
            ),
          ),
          trailing: trailing,
        ),
        if (action.consequence.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          consequence,
        ],
      ],
    );
  }
}
