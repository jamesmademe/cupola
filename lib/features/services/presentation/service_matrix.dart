/// The stack: the launcher region of the Dashboard, and the Portal's floor.
///
/// One cell per configured service, answering three questions at once:
/// *is it reachable* (the pip and the state word), *what is it doing* (two live
/// figures), and *take me there* (the whole cell is the button). That is why
/// this replaced a status grid and a separate feed: they were the same three
/// questions asked in three places.
///
/// Lives in the feature rather than in `lib/core/widgets/` because it is the
/// anatomy of exactly one screen.
///
/// ## Why there is no horizontal scroll here
///
/// The grid this replaced laid 13 services out in two rows scrolling sideways,
/// column-major, sized so the next card was clipped at 80% as a scroll hint.
/// Three things were wrong with that and all three are load-bearing for the
/// design: reading order ran top-left, bottom-left, top-right, so the grid had
/// to be decoded rather than scanned; the page scrolls vertically while the
/// primary readout scrolled horizontally, so the first two gestures fought; and
/// the single cell that matters, the one that is down, had an even chance of
/// being off-screen. A health readout you have to swipe to finish is not one.
///
/// ## One density: and what retiring the fold cost and bought
///
/// A band used to render its services at one of two densities, on a persisted
/// per-domain fold, with a container transform between them and a once-per-launch
/// demo that opened the first band and folded it shut so the user would learn the
/// affordance existed. All of it is gone.
///
/// It was a well-built answer to a question the design has since answered
/// differently. The fold existed because the stack was the *headline* of this
/// screen, sixteen cards to scroll past before reaching anything actionable,
/// so packing two thirds of them into a strip was a real saving. The stack is
/// now **fourth**: the header answers "is everything all right", the alert band
/// and the decisions region answer "what needs me", and the stack is a launcher
/// that comes after both. A launcher does not need a density preference, and the
/// preference was costing a great deal: every dimension in a cell was a lerp
/// keyed on the fold phase, the compact card could not carry a figure at all
/// (which made a folded band a health readout that had hidden the health), and a
/// page that animates on arrival once per launch is a page that moves on its own.
///
/// What is kept is the part the fold was protecting: the cards are quiet. Tone
/// and the metric's glyph arrive only when a figure asks for them, the accent is
/// a wash rather than a tile, and reachability is a *mark you only see when it
/// matters*.
///
/// ## The pip only appears when there is something to say
///
/// A pip is drawn for **checking** and **unreachable**, and for nothing else. A
/// green dot on every healthy cell is a mark present on almost every open, and a
/// mark that is always the same is one nobody reads the day it changes. An
/// answering service is proved by its figure: the number *is* the evidence that
/// something answered.
///
/// ## The header is engraved on the panel, not boxed on top of it
///
/// [_DomainBand]'s header is an eyebrow row (kicker, service count, and the
/// band's permanent health line) with no fill and no border. Grouping is
/// carried by **proximity** alone: the gap from a header up to the previous
/// band's cards is several times the gap down to its own, so a squint still
/// reveals which cards belong to which label.
///
/// It was a boxed lid once: the same `surfaceContainer`-over-`outlineVariant`
/// recipe a cell uses, and the box was the mistake: the page's own hierarchy
/// inverted, because "Stack" and "In flight" are bare text while their
/// subordinate group labels wore containers, and a full-width contained row with
/// a chevron is the visual idiom of a list row that navigates somewhere.
///
/// The health line is what makes the header worth its line, and it is
/// **permanent** now rather than appearing only while a band was shut. It used
/// to be the fold's consolation prize: the one fact a closed band would
/// otherwise swallow, which meant retiring the fold would have deleted the only
/// place a band said anything about itself.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_mark_tile.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/presentation/portal_dismiss_scope.dart';

/// Reachability of one service, as the matrix paints it.
///
/// `checking` is a state of its own rather than "offline with a different word".
/// The grid this replaced fabricated an offline summary while loading, which made
/// its border resolve to error red, so every service flashed as failed on cold
/// open, before a single request had come back.
///
/// `fault` is a state of its own for the same kind of reason: a service that
/// answered and refused the key is not a service that did not answer. It used
/// to be `offline` (red, "Unreachable", unlit), which sent the user to check a
/// cable when the fix was the key in the form. It is amber, and it stays lit:
/// the service is there.
enum ServiceReachability {
  online,
  checking,
  fault,
  offline,

  /// Not asked: away from home, with no address away. Neutral.
  onlyAtHome,
}

/// What the matrix is being asked for.
///
/// The same widget answers two different questions. On the Dashboard it is a
/// *readout*: "is anything in here wrong", and folding several connections into
/// one cell is density well spent. As the Portal's floor it is a *picker*:
/// "where do I go", and there every reachable destination has to have its own
/// cell: a picker that hides a destination is a wall.
///
/// Named for the role rather than for the shape, because the shape is the
/// consequence and the role is the cause.
enum ServiceMatrixRole { readout, picker }

/// What one cell stands for: a service folded across its connections, or one
/// named connection.
///
/// A record rather than a class hierarchy: it is two fields and it needs
/// nothing but equality, which is exactly what a record gives for free and what
/// the band's `ValueKey` depends on.
typedef MatrixCellSubject = ({ServiceKey service, String? instanceId});

/// Layout constants for the matrix grid.
class ServiceMatrixMetrics {
  ServiceMatrixMetrics._();

  /// Preferred cell width. Columns are resolved against this, not declared.
  static const double preferredCellWidth = 168;

  /// Minimum columns, per the Column Floor Rule: the count is a floor, and a
  /// single-column matrix would read as a list of unrelated rows rather than as
  /// one instrument.
  static const int minColumns = 2;

  /// Gap between cells, both axes.
  static const double gap = AppSpacing.sm;

  /// The service glyph, drawn straight on the card.
  ///
  /// No tile behind it. A 28pt rounded square holding a 16pt icon is an avatar,
  /// and sixteen of them in a grid are the visual signature of a template. The
  /// colour alone carries the identity now, which is also what lets the wash
  /// below do the rest of the work.
  static const double glyphSize = 18;

  /// Strength of the wash lighting a live card from its top-left corner.
  ///
  /// The wash is the service's accent, which is the lamp for every service
  /// (`ServiceKey.accent`): a live card is lit, an unreachable one is not, and
  /// the light says nothing about *which* service: the mark and the name do.
  /// Deliberately the same 0.14 the icon tile this replaced used for its fill,
  /// spread as light across a corner instead of stamped into a 28pt square.
  static const double accentWashAlpha = 0.14;

  /// Cell height before text growth: identity row, then the two figures.
  static const double cellBaseHeight = 96;

  /// How much of [cellBaseHeight] follows the reading size.
  ///
  /// The three text lines a card can carry (the name, the primary figure and
  /// the secondary) and nothing else. The app root installs a
  /// [DefaultTextHeightBehavior] with `applyHeightToFirstAscent` and
  /// `applyHeightToLastDescent` both false, so the leading applies only
  /// *between* lines while a block's outer edges keep the face's natural
  /// metrics (Onest's are 1.275em): a single line of `bodyLarge` measures 19.1
  /// and one of `bodySmall` 16.6, and every line in this cell is a single
  /// line.
  static const double cellTextHeight = 54;

  /// Columns that fit [availableWidth], never fewer than [minColumns].
  static int resolveColumns(double availableWidth) {
    final fit = ((availableWidth + gap) / (preferredCellWidth + gap)).floor();
    return fit < minColumns ? minColumns : fit;
  }
}

/// The whole stack: a region header, then one band per domain.
class ServiceMatrix extends ConsumerWidget {
  const ServiceMatrix({super.key, this.role = ServiceMatrixRole.readout});

  final ServiceMatrixRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    // A Seerr account that signed out is part of the stack: its cell says so.
    final configured = ServiceKey.values
        .where(settings.hasServiceConnection)
        .toList(growable: false);

    if (configured.isEmpty) return const SizedBox.shrink();

    final readout = role == ServiceMatrixRole.readout;
    final bands = <Widget>[];
    for (final domain in ServiceDomain.values) {
      final subjects = <MatrixCellSubject>[
        for (final service in domain.services)
          // One folded cell per service in the readout, including one for a
          // service nobody has set up, dimmed, leading to its settings. It used
          // to be filtered out of the band and summarised by a single
          // dismissible line under the whole matrix, which could not say *which*
          // service was missing and could be silenced permanently, leaving the
          // stack claiming to be the whole of what the user runs.
          //
          // The readout branch is written FIRST on purpose. Written the other
          // way round, Dart's dangling-else binds the `else` to the inner
          // `if (instance.isConfigured)` rather than to this one, and the
          // readout silently produces no subjects at all: a stack region that
          // renders its header and no cards.
          if (readout)
            (service: service, instanceId: null)
          // One cell per connection in the picker. No service is exempt: every
          // client resolves through the lens, so a picker cell always reaches
          // the connection it names.
          else
            ...pickerSubjectsOf(settings, service),
      ];
      if (subjects.isEmpty) continue;

      bands.add(_DomainBand(domain: domain, subjects: subjects, role: role));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...bands],
    );
  }
}

/// `4 of 5 clean · Bazarr degraded · 1 not set up`.
///
/// *Clean* is the honest word and it is not "online": a service that answers
/// while its indexers fail is up and not clean, and a header that counted it
/// as fine would contradict the amber figure on the card two rows below, or
/// the fault Needs you holds on it ([faultedServices]).
///
/// Watching these providers here costs no extra fetch: every cell in the band
/// already watches the same ones.
///
/// A provider rather than the band's own watches: the band rebuilt with every
/// read of every one of its services, and every cell under it with the band,
/// each time a summary or a figure moved. A provider of a string notifies only
/// when the line changes, so the band and its cells sit still.
final domainHealthLineProvider = Provider.autoDispose.family<String?, ServiceDomain>((
  ref,
  domain,
) {
  final settings = ref.watch(currentSettingsProvider);
  final faulted = faultedServices(
    ref.watch(dashboardDecisionsProvider).decisions,
  );
  var configured = 0;
  var clean = 0;
  var notSetUp = 0;
  var onlyAtHome = 0;
  final qualifiers = <String>[];

  for (final service in domain.services) {
    if (!settings.hasServiceConnection(service)) {
      notSetUp++;
      continue;
    }
    // Only a Seerr account that signed out: counted apart, as the stack's
    // own header counts it, neither among the services that answered nor
    // among those to set up.
    if (!settings.isServiceConfigured(service)) {
      // A secret this device would not hand over is a fault Needs you
      // holds, named as one; a Seerr account that signed out is not.
      qualifiers.add(
        settings.unreadConnectionOf(service) != null
            ? '${service.title} needs a look'
            : '${service.title} signed out',
      );
      continue;
    }
    configured++;

    final folded = ref.watch(foldedServiceHealthProvider(service));
    final summary = ref.watch(serviceSummaryProvider(service));
    final reachability = serviceReachabilityOf(summary);

    // The lens resting on a signed-out connection beside a working one:
    // the person's step, not a fault to look at.
    if (_failureOf(summary) == ServiceFailureReason.sessionEnded) {
      qualifiers.add('${service.title} signed out');
      continue;
    }

    // A connection reached that never replied is no answer either.
    final silent = folded.offline + folded.stuck;
    if (folded.total > 1 && silent > 0 && silent < folded.total) {
      qualifiers.add('${service.title} degraded');
      continue;
    }
    if (reachability == ServiceReachability.offline) {
      qualifiers.add('${service.title} did not answer');
      continue;
    }
    // A refusal or a fault: it answered, so it is not "did not answer", and
    // it is not clean either. The cell below, or Needs you, names which
    // fault.
    if (reachability == ServiceReachability.fault ||
        folded.faulted > 0 ||
        faulted.contains(service)) {
      qualifiers.add('${service.title} needs a look');
      continue;
    }
    if (reachability == ServiceReachability.onlyAtHome) {
      // Not asked, away from home: a setup, never a verdict, out of the
      // count `clean` is said against, and counted once after the rest,
      // as the header counts it: five names said nothing a figure didn't.
      configured--;
      onlyAtHome++;
      continue;
    }
    if (reachability == ServiceReachability.checking) {
      // Not a fault and not clean: nothing has failed, we simply do not know
      // yet. Counted out of `clean` so the line cannot claim a service is fine
      // before it has answered, and named without a verdict.
      qualifiers.add('${service.title} checking');
      continue;
    }

    // The same provider the cell paints from, so the line and the card
    // cannot disagree about a folded service.
    final signalState = folded.total > 1
        ? ref.watch(foldedServiceSignalPairProvider(service))
        : ref.watch(serviceSignalPairProvider(service));
    // Clean is a claim about the figures, and a card still waiting for them,
    // or showing a dash because they failed, has not made one. Counting either
    // as clean put "3 of 3 clean" over a Dockge card that never resolved.
    if (signalState.hasError && !signalState.isLoading) {
      qualifiers.add('${service.title} $servicesFiguresUnavailableLabel');
      continue;
    }
    if (!signalState.hasValue) {
      qualifiers.add('${service.title} checking');
      continue;
    }
    final signal = signalState.value;
    final flagged =
        signal != null &&
        (signal.primary.tone == StatusTone.warning ||
            signal.secondary?.tone == StatusTone.warning);
    if (flagged) {
      qualifiers.add('${service.title} needs a look');
    } else {
      clean++;
    }
  }

  if (configured == 0) {
    // A band whose only connection signed out still says so, and one away
    // from home whose every service works only there.
    return qualifiers.isEmpty && onlyAtHome == 0
        ? null
        : [
            ...qualifiers,
            if (onlyAtHome > 0) '$onlyAtHome ${StateWord.onlyAtHome.inline}',
            if (notSetUp > 0) '$notSetUp not set up',
          ].join(dotSeparator);
  }
  return serviceDomainHealthLine(
    clean: clean,
    total: configured,
    qualifiers: qualifiers,
    onlyAtHome: onlyAtHome,
    notSetUp: notSetUp,
  );
});

/// One domain of the stack: an engraved header over its cards.
class _DomainBand extends ConsumerWidget {
  const _DomainBand({
    required this.domain,
    required this.subjects,
    required this.role,
  });

  final ServiceDomain domain;
  final List<MatrixCellSubject> subjects;

  /// What the matrix is being asked for: see [ServiceMatrixRole].
  ///
  /// Carried down rather than inferred from whether a subject names a
  /// connection: the rules that hang off this (no live figure, no health line),
  /// are rules about the role.
  final ServiceMatrixRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = role == ServiceMatrixRole.readout
        ? ref.watch(domainHealthLineProvider(domain))
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          label: domain.label,
          value: joinSpokenParts([
            serviceDomainBandValue(serviceCount: subjects.length),
            if (health != null) spokenFromDotted(health),
          ]),
          excludeSemantics: true,
          child: role == ServiceMatrixRole.readout
              ? _roomHeading(context, health: health)
              : _engravedHeader(context, health: health),
        ),
        _ServiceMatrixBand(subjects: subjects, role: role),
      ],
    );
  }

  /// The engraved label: see "The header is engraved on the panel" in the
  /// library doc. No container: an eyebrow kicker with the service count and the
  /// band's health line. Grouping is carried by the asymmetric gaps alone.
  /// The readout's heading: the group's name in the room's section face,
  /// how it stands under it.
  Widget _roomHeading(BuildContext context, {required String? health}) {
    final room = CupolaRoom.of(context);
    final parts = health == null ? const <String>[] : splitParts(health);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(domain.label, style: AppType.section.copyWith(color: room.ink)),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final (index, part) in parts.indexed)
                  Text(
                    index < parts.length - 1 ? '$part\u00A0·' : part,
                    style: AppType.meta.copyWith(color: room.inkTertiary),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _engravedHeader(BuildContext context, {required String? health}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dim =
        theme.extension<CupolaThemeColors>()?.dimText ??
        colorScheme.onSurfaceVariant;
    final parts = health == null ? const <String>[] : splitParts(health);

    return Padding(
      // Generous above, tight below: the gap that separates this header from the
      // *previous* band's cards is deliberately several times the gap to its own
      // cards underneath. Proximity is the grouping cue.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            domain.label,
            style: AppTheme.chrome(
              context,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '· ${subjects.length}',
            style: AppTheme.chrome(context, color: dim),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (health != null)
            Expanded(
              // A part at a time, its dot with it: on a phone three faults
              // ran past one line, and the last fell under an ellipsis or
              // broke inside itself (`Sonarr needs a` | `look`).
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                children: [
                  for (final (index, part) in parts.indexed)
                    Text(
                      index < parts.length - 1 ? '$part\u00A0·' : part,
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                    ),
                ],
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }
}

/// The picker's cells for [service]: one per configured connection, in the
/// user's order.
///
/// Public because the floor is not the only thing that has to count them: the
/// Portal says how many services its floor holds when it opens, and a count
/// taken any other way is a count that can disagree with the cells under the
/// reader's finger.
Iterable<InstanceRef> pickerSubjectsOf(
  SettingsModel settings,
  ServiceKey service,
) => [
  for (final instance in settings.configuredInstancesOf(service))
    (service: service, instanceId: instance.id),
];

/// Reachability as the matrix paints it, from one summary.
///
/// Public for the reason [pickerSubjectsOf] is: whatever speaks about the
/// floor's cells has to read their state the way the cells do.
///
/// A probe being read again keeps the verdict of the last one: Riverpod draws
/// a reload as `AsyncLoading` carrying the previous answer, and reading only
/// `AsyncData` turned every poll into a flash of *checking* on the cell's pip
/// and on its band's line, and rebuilt the band twice for it.
ServiceReachability serviceReachabilityOf(AsyncValue<ServiceSummary> summary) =>
    switch (summary) {
      AsyncValue(:final error?) =>
        failureDidNotAnswer(classifyConnectionFailure(error))
            ? ServiceReachability.offline
            : ServiceReachability.fault,
      AsyncValue(:final value?) => switch (value.status) {
        ServiceSummaryStatus.online => ServiceReachability.online,
        ServiceSummaryStatus.fault => ServiceReachability.fault,
        ServiceSummaryStatus.offline => ServiceReachability.offline,
        ServiceSummaryStatus.onlyAtHome => ServiceReachability.onlyAtHome,
        // A cell is drawn only for a configured connection: one read as not
        // set up lost its key a moment ago, and its cell goes with the next
        // build. Until then it says nothing about the server.
        ServiceSummaryStatus.notSetUp => ServiceReachability.checking,
      },
      _ => ServiceReachability.checking,
    };

/// Why the probe behind [summary] failed, when it did. A reload keeps the
/// last probe's reason, as [serviceReachabilityOf] keeps its verdict.
ServiceFailureReason? _failureOf(AsyncValue<ServiceSummary> summary) =>
    switch (summary) {
      AsyncValue(:final error?) => classifyConnectionFailure(error),
      AsyncValue(:final value?) => value.failureReason,
      _ => null,
    };

/// What answered in front of the service behind [summary], when a gateway
/// did: the state word names it.
AccessGatewayAnswer? _gatewayOf(AsyncValue<ServiceSummary> summary) =>
    switch (summary) {
      AsyncData(:final value) => value.failure?.gateway,
      AsyncError(:final error) => accessGatewayOf(error),
      _ => null,
    };

/// Where every card in one grid sits.
///
/// Still not a `GridView`: this sits inside the page's own scroll view, and a
/// nested scrollable would need shrink-wrapping and physics juggling for a grid
/// that never scrolls on its own. A `Wrap` would do the job too and is what this
/// is, laid out explicitly so the row height is the same for every card in a row
/// regardless of how many figures each carries.
class _ServiceMatrixBand extends StatelessWidget {
  const _ServiceMatrixBand({required this.subjects, required this.role});

  final List<MatrixCellSubject> subjects;
  final ServiceMatrixRole role;

  @override
  Widget build(BuildContext context) {
    // The readout is a list: one slab per group, a row per service.
    if (role == ServiceMatrixRole.readout) {
      final room = CupolaRoom.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: room.fillQuiet,
            borderRadius: BorderRadius.circular(AppRadius.group),
            border: Border.all(color: room.fillControl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, subject) in subjects.indexed) ...[
                if (index > 0)
                  Divider(height: 1, thickness: 1, color: room.hair),
                ServiceMatrixCell(
                  key: ValueKey(subject),
                  service: subject.service,
                  instanceId: subject.instanceId,
                  role: role,
                ),
              ],
            ],
          ),
        ),
      );
    }
    // The box grows by the clamped scale, so the text has to be laid out at the
    // same clamp or the two disagree: `boxHeight` stops growing at 1.6x by
    // design ("compact chrome ellipsises rather than clipping"), but a `Text`
    // reads the ambient scaler, so at 3x the cell would be sized for 1.6 and
    // painted at 3. That is the overflow stripe, not an ellipsis.
    final clamped = TextScaleMetrics.clampedScalerOf(context);
    final cellHeight = TextScaleMetrics.boxHeight(
      context,
      base: ServiceMatrixMetrics.cellBaseHeight,
      textHeight: ServiceMatrixMetrics.cellTextHeight,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = ServiceMatrixMetrics.resolveColumns(
            constraints.maxWidth,
          );
          final gaps = ServiceMatrixMetrics.gap * (columns - 1);
          final cellWidth = (constraints.maxWidth - gaps) / columns;

          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clamped),
            child: Wrap(
              spacing: ServiceMatrixMetrics.gap,
              runSpacing: ServiceMatrixMetrics.gap,
              children: [
                for (final subject in subjects)
                  SizedBox(
                    width: cellWidth,
                    height: cellHeight,
                    child: ServiceMatrixCell(
                      // Keyed by subject, so the element (and the ink, the
                      // press state, the provider subscriptions) follows the
                      // card rather than being recycled into whichever card
                      // happens to land at that index.
                      key: ValueKey(subject),
                      service: subject.service,
                      instanceId: subject.instanceId,
                      role: role,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One service: identity, reachability, and its two live figures.
class ServiceMatrixCell extends ConsumerWidget {
  const ServiceMatrixCell({
    super.key,
    required this.service,
    this.instanceId,
    this.role = ServiceMatrixRole.readout,
  });

  final ServiceKey service;

  /// The connection this cell stands for, or null when it stands for the
  /// service folded across all of them. See [ServiceMatrixRole].
  final String? instanceId;

  /// What this cell is being asked for. Decides whether it carries live figures:
  /// the signal provider answers for the *lens*, so on a picker (where the
  /// whole point is that the cell stands for one destination rather than for
  /// whichever one is currently being read), a figure is a right number under
  /// the wrong name.
  final ServiceMatrixRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instanceId = this.instanceId;
    final settings = ref.watch(currentSettingsProvider);
    // A Seerr account that signed out has a connection: its cell reads signed
    // out, from the probe, rather than offering to set up what is set up.
    final configured = settings.hasServiceConnection(service);

    // A service nobody has set up is a cell that says so and leads to the one
    // screen that can change it. It is not a fault, so it is drawn dimmed rather
    // than dark, and it carries no pip: nothing has been asked, so there is
    // nothing to report.
    if (!configured && instanceId == null) {
      return _NotSetUpCell(
        service: service,
        asRow: role == ServiceMatrixRole.readout,
      );
    }

    final summary = instanceId == null
        ? ref.watch(serviceSummaryProvider(service))
        : ref.watch(
            instanceSummaryProvider((service: service, instanceId: instanceId)),
          );
    final instance = instanceId == null
        ? null
        : settings.instanceById(instanceId);

    final reachability = serviceReachabilityOf(summary);

    // Folded across every connection of this service. With one it says exactly
    // what `summary` already said; with more it is the only thing that can
    // answer "is anything in here down", which is the question this cell exists
    // to answer.
    //
    // Only a folded cell folds. A picker cell stands for exactly one connection
    // and reports that connection's own state: reading the service's rollup
    // there would mark a healthy server offline because a different one is.
    final folded = instanceId == null
        ? ref.watch(foldedServiceHealthProvider(service))
        : null;
    final degraded =
        folded != null && folded.total > 1 && folded.offline + folded.stuck > 0;

    // The lens, on a folded cell that has more than one connection to fold.
    // Watched conditionally for the same reason the signals below are: this is
    // the only shape of cell that has anything to say about it.
    final lens = folded != null && settings.hasMultipleInstances(service)
        ? ref.watch(activeInstanceProvider(service))
        : null;

    // The address lives on the picker's cells and on the service home, not on
    // the readout: `home` §4 is explicit, and the readout card needs the line
    // for its second figure. A picker cell still names where it points, which is
    // the whole reason that floor exists.
    final host = instance != null
        ? service.extractHost(instance.url) ?? instance.url
        : '';

    // A folded cell with more than one connection asks for the *fleet's*
    // figures; everything else asks for the connection it stands for. The two
    // providers reduce the same KPI list through the same ranking, so the split
    // changes which servers are counted and nothing else.
    //
    // Only asked for once the service has answered. Watching it while offline
    // would fan out a library fetch per unreachable service on every rebuild,
    // and there is nothing to paint with the result.
    final signalState =
        role == ServiceMatrixRole.readout &&
            reachability == ServiceReachability.online
        ? (folded != null && folded.total > 1
              ? ref.watch(foldedServiceSignalPairProvider(service))
              : ref.watch(serviceSignalPairProvider(service)))
        : null;
    // `value`, not `asData`: a pull to refresh reloads every signal, and
    // `asData` is null while one reloads, so every cell went back to the
    // shimmer for a figure it was still holding.
    final signals = signalState?.value;
    // A figure that failed is not a figure still coming. Both left `signals`
    // null, and null drew the shimmer, so a service that answered its probe
    // and then failed its read shimmered for good: a Dockge whose stack push
    // timed out sat on "coming" until the app was restarted. A retry in flight
    // is still coming, which is why a reloading error does not count.
    final signalsFailed =
        signalState != null && signalState.hasError && !signalState.isLoading;

    // A folded cell whose connections all answered, some with a fault, is a
    // fault: never better than its worst connection, and never "did not
    // answer" about servers that did.
    final foldedFault =
        folded != null &&
        folded.total > 1 &&
        folded.offline == 0 &&
        folded.faulted > 0;

    return _ServiceMatrixCellBody(
      service: service,
      role: role,
      // A folded cell never reports a better state than its worst connection.
      reachability: degraded
          ? ServiceReachability.offline
          : foldedFault
          ? ServiceReachability.fault
          : reachability,
      failure: _failureOf(summary),
      failureGateway: _gatewayOf(summary),
      faultedOf: foldedFault ? folded : null,
      // And it never shows a live figure summed over an incomplete set: a total
      // that silently drops an unreachable connection is a wrong number, not a
      // partial one.
      signals: degraded ? null : signals,
      signalsFailed: !degraded && signalsFailed,
      host: host,
      degradedOf: degraded ? folded : null,
      instanceId: instanceId,
      // The `×2` a folded multi-connection cell carries. Null on a picker cell,
      // which stands for one connection and would be claiming the wrong thing.
      instanceCount: lens == null
          ? null
          : settings.configuredInstancesOf(service).length,
      // A picker cell is named for the connection; the service is already said
      // by the glyph and the accent beside it. Named by the app's one rule, so
      // a connection the user never named reads `Radarr 2` beside its sibling
      // rather than a second bare "Radarr", and never its host: the host is
      // on the line below it, and a cell whose *title* is an address reads as
      // a different kind of object from its neighbours.
      displayName: instance == null
          ? service.shortTitle
          : settings.connectionName(instance.id) ?? service.shortTitle,
    );
  }
}

/// The cell for a service that has never been set up.
///
/// Dimmed but a real destination: the Column Floor Rule's cousin, a stack that
/// silently omits what you have not connected cannot be read as an inventory,
/// and the one action it needs is one tap away.
class _NotSetUpCell extends StatelessWidget {
  const _NotSetUpCell({required this.service, this.asRow = false});

  final ServiceKey service;

  /// A row of the readout's list rather than a card of the picker's grid.
  final bool asRow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (asRow) {
      final room = CupolaRoom.of(context);
      return AppCard.surfaceOutlined(
        key: ValueKey('service-matrix-cell-${service.routeParam}'),
        onTap: () => context.push(ServiceRoutes.setUp(service)),
        pressFeedback: AppCardPressFeedback.scale,
        semanticLabel: service.title,
        semanticValue: servicesNotSetUpCellLabel,
        excludeChildSemantics: true,
        backgroundColor: Colors.transparent,
        borderColor: Colors.transparent,
        borderRadius: BorderRadius.zero,
        padding: _rowPadding,
        child: Row(
          children: [
            Opacity(opacity: 0.5, child: ServiceMarkTile(icon: service.icon)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    Lexicon.setUp(service.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.row.copyWith(color: room.inkSecondary),
                  ),
                  Text(
                    servicesNotSetUpCellLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta.copyWith(color: room.inkTertiary),
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: room.edge),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 18,
                color: room.inkSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard.surfaceOutlined(
      key: ValueKey('service-matrix-cell-${service.routeParam}'),
      // The service's own setup form, like every other `Set up X`: the
      // connections list made the user find, a second time, the service
      // they had just tapped.
      onTap: () => context.push(ServiceRoutes.setUp(service)),
      pressFeedback: AppCardPressFeedback.scale,
      semanticLabel: service.title,
      semanticValue: servicesNotSetUpCellLabel,
      excludeChildSemantics: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.borderRadiusLg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                service.icon,
                size: ServiceMatrixMetrics.glyphSize,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  service.shortTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.weight(FontWeight.w600)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          Text(
            servicesNotSetUpCellLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.extension<CupolaThemeColors>()?.dimText ??
                  colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The painted cell, split from the provider reads so every state is reachable
/// by passing values in rather than by staging a container.
class _ServiceMatrixCellBody extends ConsumerWidget {
  const _ServiceMatrixCellBody({
    required this.service,
    required this.reachability,
    required this.signals,
    this.signalsFailed = false,
    required this.host,
    required this.role,
    this.degradedOf,
    this.faultedOf,
    this.failure,
    this.failureGateway,
    this.instanceId,
    this.instanceCount,
    required this.displayName,
  });

  /// Why the probe failed, for the state word of a single connection. Null
  /// while answering or still asking.
  final ServiceFailureReason? failure;

  /// What answered in front of the service, when [failure] is a gateway's.
  final AccessGatewayAnswer? failureGateway;

  /// Set only when this service has more than one connection, none dark and
  /// at least one answering with a fault.
  final FoldedServiceHealth? faultedOf;

  /// What the matrix is being asked for. Decides whether the live lines are
  /// rendered at all: see [ServiceMatrixCell.role].
  final ServiceMatrixRole role;

  /// Set on a picker cell, and what makes its key and its destination differ
  /// from the folded cell for the same service.
  final String? instanceId;

  /// How many connections this cell folds, when it folds more than one.
  final int? instanceCount;

  /// What this cell calls itself.
  final String displayName;

  /// Set only when this service has more than one connection and at least one
  /// of them is unreachable. The state word then counts rather than naming a
  /// state: "1 of 3 offline" is the whole of what the user needs from here.
  final FoldedServiceHealth? degradedOf;

  final ServiceKey service;
  final ServiceReachability reachability;
  final ServiceSignalPair? signals;

  /// The service answered its probe and its figures did not arrive. Drawn as
  /// an em dash rather than the in-flight shimmer: see [_CellLiveLine].
  final bool signalsFailed;
  final String host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // A service that answered (cleanly or with a fault) stays lit: it is
    // there, and a refused key is not a dark box.
    final answered =
        reachability == ServiceReachability.online ||
        reachability == ServiceReachability.fault;
    // A service that did not answer recedes instead of changing colour: the
    // surface steps *down* the ladder so the cell reads as unlit. A brightness
    // step survives colour blindness, which a red border does not.
    final surface = answered
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerLow;
    // The tone of a fault-shaped state, from its cause: amber for a fault,
    // blue for a Seerr account that signed out, which is the person's step.
    final faultTone = failureTone(failure ?? ServiceFailureReason.unknown);

    // A folded cell counts rather than naming a state. "Did not answer" on a
    // Radarr with three connections and one dark is false in both directions:
    // two of them are answering, and saying so would hide the one that is not.
    final folded = degradedOf;
    final faulted = faultedOf;
    final statusLabel = folded != null
        ? _silentOf(folded)
        : faulted != null
        ? '${faulted.faulted} of ${faulted.total} with a fault'
        : switch (reachability) {
            ServiceReachability.online => StateWord.answering.label,
            ServiceReachability.checking => 'Checking',
            // The classification's own words: `Refused the key`, `Timed out`,
            // `Answered with an error`: the same the connection form says.
            ServiceReachability.fault => failureLabel(
              failure ?? ServiceFailureReason.unknown,
              credential: refusedCredentialOf(service),
              gateway: failureGateway,
            ),
            // A bare state word, and deliberately so: "Did not answer since
            // 20:41" needs a `firstFailedAt` notifier keyed by TLS origin and a
            // clock, neither of which exists. Inventing the time from the first
            // frame that noticed would print the time of the *observation* and
            // call it the time of the outage.
            ServiceReachability.offline => failureLabel(
              ServiceFailureReason.unreachable,
            ),
            ServiceReachability.onlyAtHome => StateWord.onlyAtHome.label,
          };

    // Resolved here rather than in the tap handler: an inherited lookup belongs
    // in build, where the dependency it registers means something. Null on the
    // Dashboard, which has no layer above it to dismiss.
    final dismissPortal = PortalDismissScope.maybeOf(context);
    // The readout's row: the mark in its tile, the name, how it stands,
    // and the way in. The picker keeps its card.
    final asRow = role == ServiceMatrixRole.readout;

    return AppCard.surfaceOutlined(
      // Suffixed only on a picker cell. The readout key is what the dashboard
      // tests address, and a folded cell still stands for the service, so the
      // name it had is still the true one.
      key: ValueKey(
        instanceId == null
            ? 'service-matrix-cell-${service.routeParam}'
            : 'service-matrix-cell-${service.routeParam}-$instanceId',
      ),
      // Two acts, not one. Navigating alone would land on whichever connection
      // the lens already pointed at (which is the cell the user did *not* tap),
      // so the lens moves first and the route follows it.
      //
      // And `go`, not `push`, because this same cell is rendered in two places:
      // on the Dashboard, and on the Portal's floor, which lives ABOVE the
      // branch navigators and can be opened from any tab. A push keeps the
      // origin branch, so travelling to Radarr from Activity would have stacked
      // a service page on the Activity tab with the bar still lit on Activity.
      //
      // Choosing a cell is also an action ON the Portal, so it closes the Portal,
      // always, before anything else is known about where it leads. The
      // shell's route hook closes on a different question ("did the content
      // under the card move?"), and the answer to that is *no* for the commonest
      // tap of all: the cell for the connection the lens already points at.
      onTap: () async {
        dismissPortal?.call();
        final id = instanceId;
        if (id != null) {
          await ref.read(activeInstancesProvider.notifier).select(service, id);
        }
        if (!context.mounted) return;
        context.go(ServiceRoutes.forService(service));
      },
      // The card dips under the thumb instead of rippling. A ripple flooding a
      // card is how a chip signals selection, not how a surface signals a touch.
      pressFeedback: AppCardPressFeedback.scale,
      // The full name aloud: the short one is for the tile's width.
      semanticLabel: displayName == service.shortTitle
          ? service.title
          : displayName,
      semanticValue: serviceMatrixCellValue(
        statusLabel: statusLabel,
        signalSpoken: signalsFailed
            ? servicesFiguresUnavailableLabel
            : signals?.primary.spoken,
        secondarySpoken: signals?.secondary?.spoken,
        instanceLabel: instanceCount == null
            ? null
            : serviceInstanceCountLabel(instanceCount!),
        host: host,
      ),
      // Nothing inside is separately interactive, and every visible fragment is
      // already in the composed value above.
      excludeChildSemantics: true,
      backgroundColor: asRow ? Colors.transparent : surface,
      borderColor: asRow ? Colors.transparent : null,
      // The light, and the only place a service accent appears on this screen.
      // Withheld from an unreachable card: a service that is not answering
      // should look unlit, and that has to include its own colour.
      accentColor: !asRow && answered ? service.accent : null,
      accentGlowAlpha: ServiceMatrixMetrics.accentWashAlpha,
      accentGlowCenter: Alignment.topLeft,
      borderRadius: asRow ? BorderRadius.zero : AppRadius.borderRadiusLg,
      padding: asRow ? _rowPadding : const EdgeInsets.all(AppSpacing.md),
      child: asRow
          ? _CellRow(
              service: service,
              displayName: displayName,
              reachability: reachability,
              faultTone: faultTone,
              instanceCount: instanceCount,
              signals: signals,
              signalsFailed: signalsFailed,
              statusLabel: statusLabel,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CellIdentity(
                  service: service,
                  displayName: displayName,
                  reachability: reachability,
                  faultTone: faultTone,
                  surface: surface,
                  instanceCount: instanceCount,
                ),
                if (role == ServiceMatrixRole.readout)
                  _CellLiveLine(
                    reachability: reachability,
                    faultTone: faultTone,
                    signals: signals,
                    signalsFailed: signalsFailed,
                    statusLabel: statusLabel,
                    surface: surface,
                  )
                else if (host.isNotEmpty)
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.tabular.copyWith(
                      color:
                          theme.extension<CupolaThemeColors>()?.dimText ??
                          colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A readout row's padding: the row is the target, 64 tall with its tile.
const _rowPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);

/// One service as a row of the readout's list.
class _CellRow extends StatelessWidget {
  const _CellRow({
    required this.service,
    required this.displayName,
    required this.reachability,
    required this.faultTone,
    required this.instanceCount,
    required this.signals,
    required this.signalsFailed,
    required this.statusLabel,
  });

  final ServiceKey service;
  final String displayName;
  final ServiceReachability reachability;
  final StatusTone faultTone;
  final int? instanceCount;
  final ServiceSignalPair? signals;
  final bool signalsFailed;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final answered =
        reachability == ServiceReachability.online ||
        reachability == ServiceReachability.fault;

    // How it stands, one line: a dot of its tone, then the words.
    final (StatusTone tone, Object state) = switch (reachability) {
      ServiceReachability.online when signals == null && signalsFailed => (
        StatusTone.neutral,
        Text(
          ServiceKpi.unavailableValue,
          style: AppType.meta.copyWith(color: room.inkSecondary),
        ),
      ),
      ServiceReachability.online when signals == null => (
        StatusTone.neutral,
        ShimmerPlaceholder.text(width: 96),
      ),
      ServiceReachability.online => (
        signals!.primary.needsAttention
            ? signals!.primary.tone
            : StatusTone.neutral,
        Text.rich(
          TextSpan(
            children: [
              for (final (index, signal) in [
                signals!.primary,
                ?signals!.secondary,
              ].indexed) ...[
                if (index > 0) const TextSpan(text: '\u00A0· '),
                TextSpan(
                  text: signal.value,
                  style: signal.needsAttention
                      ? TextStyle(
                          color: statusToneColor(colorScheme, signal.tone),
                        )
                      : null,
                ),
                if (signal.label.isNotEmpty) TextSpan(text: ' ${signal.label}'),
              ],
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta.tabular.copyWith(color: room.inkSecondary),
        ),
      ),
      _ => (
        switch (reachability) {
          ServiceReachability.checking ||
          ServiceReachability.onlyAtHome => StatusTone.neutral,
          ServiceReachability.fault => faultTone,
          _ => StatusTone.error,
        },
        statusLabel,
      ),
    };
    // A state that is not an answer is said in its tone (`2 requests wait
    // for your approval` in blue, `Refused the key` in amber), measured on
    // the slab; checking and only-at-home stay in the secondary ink.
    final Widget words = switch (state) {
      final String label => Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.meta.copyWith(
          color: tone == StatusTone.neutral
              ? room.inkSecondary
              : statusToneColor(
                  colorScheme,
                  tone,
                  surface: colorScheme.surfaceContainer,
                ),
        ),
      ),
      final Widget figures => figures,
      _ => const SizedBox.shrink(),
    };
    final dot = statusToneColor(colorScheme, tone);
    // The backlog is a ring, not a light: nothing is wrong, nothing is lit.
    final ring = tone == StatusTone.neutral;

    return Row(
      children: [
        Opacity(
          opacity: answered ? 1 : 0.6,
          child: ServiceMarkTile(icon: service.icon),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.row.copyWith(
                        color: answered ? room.ink : room.inkSecondary,
                      ),
                    ),
                  ),
                  if (instanceCount != null && instanceCount! > 1) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '×$instanceCount',
                      style: AppType.meta.tabular.copyWith(
                        color: room.inkTertiary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ring ? null : dot,
                      border: ring ? Border.all(color: dot, width: 1.5) : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: words),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Icon(Icons.chevron_right_rounded, size: 20, color: room.inkTertiary),
      ],
    );
  }
}

/// The glyph, the name, the `×N`, and (only when there is something to say)
/// the reachability pip.
class _CellIdentity extends StatelessWidget {
  const _CellIdentity({
    required this.service,
    required this.displayName,
    required this.reachability,
    required this.surface,
    this.faultTone = StatusTone.warning,
    this.instanceCount,
  });

  final ServiceKey service;

  /// What the cell calls itself: the service, or the connection's own name on
  /// a picker cell. The glyph and the accent already say which service it is,
  /// so the word is free to say which *one*.
  final String displayName;
  final ServiceReachability reachability;
  final Color surface;
  final int? instanceCount;

  /// The tone of a fault on this cell: see [_ReachabilityPip.faultTone].
  final StatusTone faultTone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOnline =
        reachability == ServiceReachability.online ||
        reachability == ServiceReachability.fault;

    return Row(
      children: [
        // Drawn straight on the card, no tile. Resolved through `onTint` for the
        // same reason a label over a tint is: an icon is a graphical object with
        // a 3:1 floor, and the raw accent measures about 1.9:1 on the light card
        // (Radarr's amber especially).
        Icon(
          service.icon,
          size: ServiceMatrixMetrics.glyphSize,
          color: isOnline
              ? ServiceTheme.onTint(
                  service.accent,
                  surface: surface,
                  tintAlpha: ServiceMatrixMetrics.accentWashAlpha,
                )
              : colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.weight(FontWeight.w600)
                .copyWith(
                  color: isOnline
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        if (instanceCount != null && instanceCount! > 1) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            '×$instanceCount',
            style: theme.textTheme.labelSmall?.tabular.copyWith(
              color:
                  theme.extension<CupolaThemeColors>()?.dimText ??
                  colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        // The whole pip policy, in one condition: a mark for *checking* and for
        // *unreachable*, and nothing for a service that is answering. The figure
        // below is that service's proof of life, and a green dot beside it would
        // be a second, weaker statement of the same fact: present on almost
        // every cell of almost every open, which is how a mark stops being read.
        if (reachability != ServiceReachability.online) ...[
          const SizedBox(width: AppSpacing.xs),
          _ReachabilityPip(reachability: reachability, faultTone: faultTone),
        ],
      ],
    );
  }
}

/// A tone-coloured dot. See [_CellIdentity] for when it appears at all.
class _ReachabilityPip extends StatelessWidget {
  const _ReachabilityPip({
    required this.reachability,
    this.faultTone = StatusTone.warning,
  });

  final ServiceReachability reachability;

  /// Amber for a fault; blue for a Seerr account that signed out.
  final StatusTone faultTone;

  /// 8pt, matching `components.status-dot` (the token this app uses everywhere
  /// a bare dot carries state).
  static const double _size = 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // A probe that has not come back yet is not a fault: nothing has failed, we
    // simply do not know. Amber said "something is wrong" on every cell for the
    // first second of every launch; neutral says "asking".
    //
    // Both resolve through `statusToneColor` rather than through `AppColors.*`
    // literals: the Closed Tone Rule this file's own doc comment cites, and the
    // token ImplNotes names for this archetype.
    final color = switch (reachability) {
      ServiceReachability.online => statusToneColor(
        colorScheme,
        StatusTone.success,
      ),
      ServiceReachability.checking => statusToneColor(
        colorScheme,
        StatusTone.neutral,
      ),
      // It answered and said no, or answered broken: a fault, amber. A
      // Seerr account that signed out is the one fault-shaped state that is
      // not one: blue, as the classification says.
      ServiceReachability.fault => statusToneColor(colorScheme, faultTone),
      ServiceReachability.offline => statusToneColor(
        colorScheme,
        StatusTone.error,
      ),
      // Not asked, away from home: a setup, neutral like a probe still out.
      ServiceReachability.onlyAtHome => statusToneColor(
        colorScheme,
        StatusTone.neutral,
      ),
    };

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The readout: two live figures when the service is up, the state word when it
/// is not.
///
/// One slot for both is the point. The old card spent a row on `ONLINE` next to
/// a green dot saying the same thing, and spent the row below it on a library
/// total that does not change from one week to the next: so the only genuinely
/// live line on a control-room screen was chrome.
///
/// Two figures rather than one, because one was never the whole answer: the
/// primary is the service's headline (its scale, or its fault if it has one) and
/// the secondary is the next-ranked metric, **each keeping its own tone**. A
/// Radarr reads `2 038 movies` over a neutral `34 missing`; a Bazarr reads
/// `47 wanted subs` over an amber `API key rejected`. Painting both with the
/// worse of the two would collapse the distinction the tone rule is for.
class _CellLiveLine extends StatelessWidget {
  const _CellLiveLine({
    required this.reachability,
    required this.signals,
    this.signalsFailed = false,
    required this.statusLabel,
    required this.surface,
    this.faultTone = StatusTone.warning,
  });

  final ServiceReachability reachability;

  /// Amber for a fault; blue for a Seerr account that signed out.
  final StatusTone faultTone;
  final ServiceSignalPair? signals;
  final bool signalsFailed;
  final String statusLabel;

  /// The cell's own background, which is what a tone-coloured word here is
  /// measured against. An offline cell sits a step lower on the surface ladder,
  /// so it is not the same composite as an online one.
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // One tier above the name is the whole hierarchy: the figure is the only
    // thing on the cell allowed to be larger and bolder than the service's own
    // name, and only just.
    final figureStyle = theme.textTheme.bodyLarge?.weight(FontWeight.w600);

    if (reachability != ServiceReachability.online) {
      return Text(
        statusLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: figureStyle?.copyWith(
          // `surface` is the card's own ground, not the scaffold's: the walk
          // that keeps a saturated tone legible has to measure against what the
          // label actually sits on.
          //
          // Checking is **neutral**, not amber. A probe still out is not a
          // fault, and the header says the same thing in the same breath ("N
          // checking, which is not a fault").
          //
          // A fault is amber: the service answered. Only a service that did
          // not answer is red.
          color: statusToneColor(colorScheme, switch (reachability) {
            ServiceReachability.checking ||
            ServiceReachability.onlyAtHome => StatusTone.neutral,
            ServiceReachability.fault => faultTone,
            _ => StatusTone.error,
          }, surface: surface),
        ),
      );
    }

    final current = signals;
    if (current == null && signalsFailed) {
      // Untoned, like `ServiceKpi.unavailable`: the figure's absence is not a
      // fault of the service, which has just answered its probe.
      return Text(
        ServiceKpi.unavailableValue,
        maxLines: 1,
        style: figureStyle?.copyWith(
          color:
              theme.extension<CupolaThemeColors>()?.dimText ??
              colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (current == null) {
      // Reachable, metric still in flight. A shimmer says "coming"; blank space
      // would say "nothing to report", which is a different fact.
      return ShimmerPlaceholder.text(width: 64);
    }

    final secondary = current.secondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FigureLine(
          signal: current.primary,
          style: figureStyle,
          surface: surface,
          emphasis: true,
        ),
        if (secondary != null)
          _FigureLine(
            signal: secondary,
            style: theme.textTheme.bodySmall?.weight(FontWeight.w600),
            surface: surface,
            emphasis: false,
          ),
      ],
    );
  }
}

/// One figure and its word, on one line.
class _FigureLine extends StatelessWidget {
  const _FigureLine({
    required this.signal,
    required this.style,
    required this.surface,
    required this.emphasis,
  });

  final ServiceSignal signal;
  final TextStyle? style;
  final Color surface;

  /// Whether this is the card's primary. The secondary is a step quieter in
  /// size and weight: two figures at the same weight are two headlines.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final needsAttention = signal.needsAttention;
    // Each figure keeps its own tone, resolved against the card's own ground.
    // An unflagged figure is ordinary ink, not a colour: a card where every
    // number is tinted has no way left to say which one matters.
    final toneColor = needsAttention
        ? statusToneColor(colorScheme, signal.tone, surface: surface)
        : (emphasis ? colorScheme.onSurface : colorScheme.onSurfaceVariant);

    return Row(
      children: [
        // Only when the figure is asking for something. On a healthy service the
        // glyph restates the metric word beside it, and sixteen of them turned
        // the grid into a sheet of pictograms.
        if (needsAttention && emphasis) ...[
          Icon(signal.icon, size: 13, color: toneColor),
          const SizedBox(width: AppSpacing.xs),
        ],
        // One text run, not two `Text`s in a `Row`. Two of them cannot both be
        // right. Unflexed, a wide figure cannot shrink, and a transfer rate
        // is service-supplied and `1023.9 KB/s` at the band's 1.6x clamp is
        // wider on its own than a two-column cell on a 375pt phone, which is an
        // overflow stripe rather than an ellipsis. Made flexible instead,
        // Flutter splits the free space by flex factor and never hands the
        // remainder back, so `12 missing` elided to "12 missi…" at the *default*
        // reading size with room to spare.
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  // The figure updates in place; proportional digits make it
                  // jitter.
                  text: signal.value,
                  style: style?.tabular.copyWith(color: toneColor),
                ),
                // Absent when the value is already a state word, such as "Paused", which needs
                // no "status" after it. See `ServiceSignal.label`.
                if (signal.label.isNotEmpty)
                  TextSpan(
                    text: ' ${signal.label}',
                    // Plain body, not `AppTheme.eyebrow`. The Eyebrow Rule stops
                    // at repetition: "the eyebrow earns its emphasis by being
                    // rare", and one per cell across a sixteen-cell grid is the
                    // noise the style exists to avoid.
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// How many of a folded service's connections said nothing: `1 of 3 did not
/// answer`, `1 of 3 timed out` when they were reached and never replied, and
/// `2 of 3 did not answer in time` when it was some of each.
String _silentOf(FoldedServiceHealth folded) {
  final total = folded.total;
  if (folded.stuck == 0) return '${folded.offline} of $total did not answer';
  if (folded.offline == 0) return '${folded.stuck} of $total timed out';
  return '${folded.offline + folded.stuck} of $total did not answer in time';
}
