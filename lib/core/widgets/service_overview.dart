import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_only_at_home.dart';

/// The furniture every service Overview is built out of: the identity line, the
/// section frame, the row, the empty note and the skeleton.
///
/// **It lives here because seventeen services get one of these pages and four
/// of them were already written.** Radarr, Seerr, Bazarr and Prowlarr each
/// carried a private `_OverviewSection` / `_OverviewRow` / `_SectionEmpty` /
/// `_RowsSkeleton` / `_IdentityBlock` that differed only in which `ServiceKey`
/// they named: the fifth copy would have been written before anyone noticed
/// the first four had drifted. Nine more Overviews are owed.
///
/// Everything here takes the [ServiceKey] and derives the rest: the ink by
/// [serviceOverviewInk], the tab link's destination and its spoken hint, the
/// branch a link switches to. Nothing takes a colour, because a caller passing
/// a colour is a caller that can pass a hue and put 2.4:1 text on paper.

/// The ink of an Overview's links and section marks: the room's secondary ink.
///
/// The room is monochrome (principle 3 of the brand book: colour is information), so a link
/// that opens another tab is the secondary ink the brand book draws section links
/// in, the same on every service: it used to be the service's accent, walked
/// until it cleared AA. Public because a page's own section marks have to be
/// inked the same way as the link and the lens chip here: four private copies
/// of this one expression is exactly what the rest of this file exists to
/// stop. [service] stays in the signature so every call site keeps naming
/// whose Overview it is.
Color serviceOverviewInk(ServiceKey service, ColorScheme colorScheme) =>
    colorScheme.onSurfaceVariant;

/// Switches to another of [service]'s tabs.
///
/// `goBranch`, not `context.go`: it restores that branch's own stack, which is
/// what makes "back returns to the tab you left" true. `maybeOf` rather than
/// `of` because an Overview is also legitimately built outside a shell, a
/// widget test, a preview, where there is no branch to switch and the link
/// simply does nothing rather than throwing.
void _goToTab(BuildContext context, ServiceKey service, ServiceTab tab) {
  final tabs = tabsFor(service);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
}

/// One region of a service Overview: a header, a body, and the air after it.
class ServiceOverviewSection extends StatelessWidget {
  /// The ordinary region, whose body is inset to the page column.
  const ServiceOverviewSection({
    super.key,
    required this.service,
    required this.title,
    required this.child,
    this.subtitle,
    this.destination,
  }) : padBody = true;

  /// A region whose body bleeds to the window edge: a poster rail, whose first
  /// tile aligns to the column while the row itself runs off it.
  ///
  /// A named constructor rather than a `padBody:` flag, per
  /// `lib/core/widgets/AGENTS.md`: the call site says which shape it is
  /// building instead of setting a mode on a general one.
  const ServiceOverviewSection.bleed({
    super.key,
    required this.service,
    required this.title,
    required this.child,
    this.subtitle,
    this.destination,
  }) : padBody = false;

  /// Whose Overview this is. It decides the link's ink and which shell the link
  /// switches a branch on.
  final ServiceKey service;

  final String title;
  final String? subtitle;

  /// The tab this region's "see the rest" link opens, or null for a region
  /// whose rows belong to several tabs at once.
  final ServiceTab? destination;

  final Widget child;

  /// False for [ServiceOverviewSection.bleed].
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tab = destination;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          showChevron: false,
          trailing: tab == null
              ? null
              : _TabLink(
                  label: tab.label,
                  color: serviceOverviewInk(service, colorScheme),
                ),
          // The link's "→" sits inside the region the header silences. Read
          // out it is "rightwards arrow", so the destination comes back as a
          // hint instead.
          semanticHint: tab == null
              ? null
              : 'opens the ${service.title} ${tab.label} tab',
          onTap: tab == null ? null : () => _goToTab(context, service, tab),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (padBody)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: child,
          )
        else
          child,
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _TabLink extends StatelessWidget {
  const _TabLink({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label →',
      // One line, always: the arrow belongs to the word before it, and stranded
      // on a line of its own it reads as a second control.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.weight(FontWeight.w600).copyWith(color: color),
    );
  }
}

/// The widest a [ServiceOverviewRow.trailing] figure may be.
///
/// Capped rather than free: at an accessibility reading size an unconstrained
/// figure next to an `Expanded` title is a right-edge overflow, and a row that
/// throws is worse than a figure that ellipsises. The whole value is still in
/// the sentence a screen reader hears.
const double _trailingMaxWidth = 132;

/// Two lines and a leading mark: the one row shape every Overview section uses.
class ServiceOverviewRow extends StatelessWidget {
  const ServiceOverviewRow({
    super.key,
    required this.spoken,
    required this.leading,
    required this.title,
    required this.detail,
    this.titleColor,
    this.trailing,
  });

  /// The whole row as one sentence, with the layout's `·` turned back into
  /// commas.
  final String spoken;

  final Widget leading;
  final String title;
  final String detail;

  /// Ink for the title where a row states its own tone; otherwise
  /// `onSurface`. It is passed already resolved, because the tone a row is
  /// carrying is the page's fact, not this widget's.
  final Color? titleColor;

  /// The right-hand figure, e.g. `298 queries`. Already folded into [spoken],
  /// which is why the row can silence its own subtree.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Semantics(
      container: true,
      label: spoken,
      // Nothing in this row is interactive, so the parts are safe to silence:
      // read separately they are three fragments of one fact.
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.data(
                      brightness,
                    ).copyWith(color: titleColor ?? colorScheme.onSurface),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTheme.chrome(
                        context,
                        size: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _trailingMaxWidth),
                child: Text(
                  trailing!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTheme.chrome(
                    context,
                    size: 11,
                    weight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The "nothing here" note for a region at rest.
///
/// [AppEmptyState.inline] and not the 72dp well: nothing failed and nothing is
/// missing, so the absence costs a row rather than a screenful of ceremony.
class ServiceOverviewEmpty extends StatelessWidget {
  const ServiceOverviewEmpty({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState.inline(icon: icon, title: label);
  }
}

/// The loading shape of a rows region: [rows] two-line ghosts.
class ServiceOverviewRowsSkeleton extends StatelessWidget {
  const ServiceOverviewRowsSkeleton({super.key, required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerPlaceholder.text(width: 180, height: 14),
                const SizedBox(height: AppSpacing.xs),
                ShimmerPlaceholder.text(width: 120, height: 10),
              ],
            ),
          ),
      ],
    );
  }
}

/// Host, version, whether it is answering, and which connection you are
/// reading.
class ServiceOverviewIdentity extends ConsumerWidget {
  const ServiceOverviewIdentity({super.key, required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final summary = ref.watch(serviceSummaryProvider(service));
    final instance = ref.watch(activeInstanceProvider(service));
    final hasLens = ref.watch(hasMultipleInstancesProvider(service));

    // The probe reduced to the connection vocabulary, **with its reason**. A
    // summary still in flight is `checking` rather than a guess. A failed one
    // says why: without the reason every failure read red "did not answer",
    // so a Radarr that refused the key sat under the same word as one that
    // was switched off.
    final status = summary.when(
      loading: () => ServiceConnectionStatus.checking,
      error: (_, _) => ServiceConnectionStatus.disconnected,
      data: (value) => value.isOnline
          ? ServiceConnectionStatus.connected
          : ServiceConnectionStatus.disconnected,
    );
    final reason = summary.when(
      loading: () => null,
      error: (error, _) => classifyConnectionFailure(error),
      data: (value) => value.failureReason,
    );
    final presentation = describeConnection(
      service,
      status: status,
      reason: reason,
      gateway: summary.when(
        loading: () => null,
        error: (error, _) => accessGatewayOf(error),
        data: (value) => value.failure?.gateway,
      ),
    );
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    final host = service.extractHost(instance?.url);
    // A figure whose source did not answer reads "—", never a fallback dressed
    // up as an answer: `ServiceSummary.versionLabel` degrades to "v3 API" when
    // the service named no version, which is honest for a server that replied
    // and a fabrication for one that never did.
    final summaryData = summary.asData?.value;
    final version = summaryData != null && summaryData.isOnline
        ? summaryData.versionLabel
        : null;
    // The app's one rule for naming a connection: with two, a connection the
    // user never named still reads `Radarr 2` rather than nothing at all.
    final lens = hasLens && instance != null
        ? ref.watch(connectionNameProvider(instance.id))
        : null;

    final facts = <String>[
      host == null || host.isEmpty ? '—' : host,
      version == null || version.isEmpty ? '—' : version,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Semantics(
        container: true,
        // One sentence rather than four stops: the host alone, read out on its
        // own, does not say what it is the host of.
        label: joinSpokenParts([
          service.title,
          ...facts,
          presentation.label,
          if (lens != null && lens.isNotEmpty) lens,
        ]),
        excludeSemantics: true,
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              facts.join(' · '),
              style: AppTheme.chrome(
                context,
                size: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            // Tone and glyph both, because colour is not information: the word
            // is the channel that always works.
            _StatusWord(
              icon: presentation.icon,
              label: presentation.label,
              color: toneColor,
            ),
            if (lens != null && lens.isNotEmpty)
              _LensChip(service: service, label: lens),
          ],
        ),
      ),
    );
  }
}

class _StatusWord extends StatelessWidget {
  const _StatusWord({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTheme.chrome(
            context,
            size: 12,
            weight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _LensChip extends StatelessWidget {
  const _LensChip({required this.service, required this.label});

  final ServiceKey service;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: AppTheme.chrome(
          context,
          size: 11,
          weight: FontWeight.w600,
          color: serviceOverviewInk(service, colorScheme),
        ),
      ),
    );
  }
}

/// An Overview's [sections], or the one line that stands for all of them,
/// when every section is bound to fail for one reason the page can name
/// before asking:
///
///  * away from home, for a lens connection with no address away: every
///    request is refused before it is sent ([ServiceOnlyAtHome]), and each
///    section said so in the same sentence with the same remedy, three times
///    in Seerr's first screen under a figure peek of dashes. Said once
///    instead, under the identity line that already reads `Only at home`,
///    with `Add an address away` as its one action;
///  * for a lens connection neither of whose addresses answered the route
///    probe ([ServiceFailureReason.unreachableAtBoth]): the red names both
///    addresses once, and its Retry knocks at both.
///
/// A spread rather than a wrapper, so the page's list keeps building its
/// sections lazily; called from the page's build with its [ref].
List<Widget> sectionsOrOneLine(
  WidgetRef ref,
  ServiceKey service,
  List<Widget> sections,
) {
  final reason = ref.watch(
    serviceSummaryProvider(
      service,
    ).select((summary) => summary.asData?.value.failureReason),
  );
  return switch (reason) {
    ServiceFailureReason.onlyAtHome => [
      ServiceOverviewOnlyAtHome(service: service),
    ],
    ServiceFailureReason.unreachableAtBoth => [
      ServiceOverviewUnanswered(service: service),
    ],
    _ => sections,
  };
}

/// The one line of an Overview whose lens connection answered at neither of
/// its addresses: `Radarr did not answer at home or away`, then where, one
/// address a line. Red, and its Retry (a ghost in ink) asks both again
/// (`retryDashboardServices`). See [sectionsOrOneLine].
class ServiceOverviewUnanswered extends ConsumerWidget {
  const ServiceOverviewUnanswered({super.key, required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(activeInstanceProvider(service));
    final name =
        (ref.watch(hasMultipleInstancesProvider(service)) && instance != null
            ? ref.watch(connectionNameProvider(instance.id))
            : null) ??
        service.title;
    final unanswered = instance == null
        ? null
        : ref.watch(unansweredConnectionProvider(instance.id));
    final headline = failureHeadline(
      ServiceFailureReason.unreachableAtBoth,
      subject: name,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: InlineErrorRetry.flush(
        message: unanswered == null
            ? '$headline.'
            : '$headline.\n${unanswered.failureDetail}',
        error:
            unanswered ??
            const ClassifiedFailure(ServiceFailureReason.unreachableAtBoth),
        service: service,
        instanceId: instance?.id,
        onRetry: () => retryDashboardServices(ref, [service]),
      ),
    );
  }
}

/// The one line of an Overview whose connection is reached only at home,
/// read away from home: see [sectionsOrOneLine].
class ServiceOverviewOnlyAtHome extends ConsumerWidget {
  const ServiceOverviewOnlyAtHome({super.key, required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(activeInstanceProvider(service));
    // The connection by its name when there are two: the other Radarr may
    // well have an address away.
    final name =
        (ref.watch(hasMultipleInstancesProvider(service)) && instance != null
            ? ref.watch(connectionNameProvider(instance.id))
            : null) ??
        service.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      // On the page column, its glyph under the identity line's first fact.
      child: InlineErrorRetry.flush(
        message:
            '$name has no address away, so Cupola reaches it only on your '
            'home Wi-Fi.',
        error: ServiceOnlyAtHome(service),
        service: service,
        instanceId: instance?.id,
        // Never offered: the same request is refused again until the app is
        // home, or the connection has an address away.
        onRetry: () {},
      ),
    );
  }
}
