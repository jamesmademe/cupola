import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
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
///
/// Public because a row that leads to a sibling tab (an attention row whose
/// faults that tab lists) switches the branch the same way the section link
/// does.
void goToServiceTab(BuildContext context, ServiceKey service, ServiceTab tab) {
  final tabs = tabsFor(service);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
}

/// What a screen reader is told about where [door] leads, read after the
/// row's own sentence: the chevron is the only visual mark of a door, and a
/// chevron has no name.
String attentionDoorHint(ServiceKey service, AttentionDoor door) =>
    switch (door) {
      AttentionTab(:final tab) => 'opens the ${service.title} ${tab.label} tab',
      AttentionDownload() => 'opens this download',
      AttentionPage(:final hint) => hint,
    };

/// Goes through [door] from a row of [service]'s Overview.
///
/// A tab by `goBranch` ([goToServiceTab]); a download or a page by the
/// router, through `open_media.dart` where a title or a download is opened
/// (a download's page goes beside its list on a tablet). Outside a router (a
/// widget test, a preview) there is nowhere to go, and nothing happens
/// rather than a throw: the same rule as the section link.
void openAttentionDoor(
  BuildContext context,
  ServiceKey service,
  AttentionDoor door,
) {
  switch (door) {
    case AttentionTab(:final tab):
      goToServiceTab(context, service, tab);
    case AttentionDownload(:final instanceId, :final key):
      if (GoRouter.maybeOf(context) == null) return;
      context.openDownloadAt(instanceId: instanceId, key: key);
    case AttentionPage(:final location):
      GoRouter.maybeOf(context)?.push(location);
  }
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
          onTap: tab == null
              ? null
              : () => goToServiceTab(context, service, tab),
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

/// The floor a row that opens something reaches: the whole row is the target.
const double _doorMinHeight = 44;

/// A verb beside a row: something the app already does elsewhere, one tap
/// from here.
///
/// Data rather than a widget, so a row cannot be handed a button that breaks
/// the touch target or the spoken name: [ServiceOverviewRow] draws it.
@immutable
class ServiceOverviewRowAction {
  const ServiceOverviewRowAction({
    required this.label,
    required this.hint,
    required this.onPressed,
  });

  /// The verb, in the word the app already uses for it (`Test`, `Start`).
  final String label;

  /// What the verb acts on, said after the label: `tests Nyaa`. A button named
  /// `Test` beside a list of indexers does not say which one.
  final String hint;

  final VoidCallback onPressed;
}

/// Two lines and a leading mark: the one row shape every Overview section uses.
///
/// A row is read-only unless it is given somewhere to go. [onTap] makes it a
/// **door**: the place the row is about, one button for a screen reader that
/// speaks [spoken] and says where it leads ([doorHint]). [action] puts a verb
/// beside it, a real button of its own. A row with neither is exactly the
/// plain row it always was.
class ServiceOverviewRow extends StatelessWidget {
  const ServiceOverviewRow({
    super.key,
    required this.spoken,
    required this.leading,
    required this.title,
    required this.detail,
    this.titleColor,
    this.trailing,
    this.onTap,
    this.doorHint,
    this.action,
  }) : assert(
         (onTap == null) == (doorHint == null),
         'A door says where it leads: onTap and doorHint come together',
       );

  /// The whole row as one sentence, with the layout's `·` turned back into
  /// commas.
  final String spoken;

  /// Where the row leads, or null for a row that is only read. The whole row
  /// is the target, at least 44 tall.
  ///
  /// Drawn with a chevron, as the other rows of the app that open something
  /// are, unless the row also carries an [action]: the verb is then the mark,
  /// as it is on a Home decision row, and the body stays tappable.
  final VoidCallback? onTap;

  /// Where [onTap] goes, said after [spoken]: `opens the Prowlarr Indexers
  /// tab`. The chevron is the only visual mark of a door and has no name.
  final String? doorHint;

  /// A verb beside the row, or null. It is a button in its own right, outside
  /// the row's one sentence, so a screen reader reaches both.
  final ServiceOverviewRowAction? action;

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
    final door = onTap;
    final verb = action;

    final lines = Row(
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
    );

    // Nothing in a row that is only read is interactive, so the parts are safe
    // to silence: read separately they are three fragments of one fact.
    if (door == null) {
      final plain = Semantics(
        container: true,
        label: spoken,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: lines,
        ),
      );
      return verb == null ? plain : _withAction(plain, verb);
    }

    // A door is one button: the sentence, where it leads, and the tap. The
    // gap under the row sits inside the target, so the rows keep the rhythm
    // of the plain ones and the target still reaches 44.
    final opens = Semantics(
      container: true,
      button: true,
      label: spoken,
      hint: doorHint,
      onTap: door,
      child: InkWell(
        onTap: door,
        borderRadius: AppRadius.borderRadiusSm,
        // The name and the tap are the node above's.
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _doorMinHeight),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: lines),
                  if (verb == null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return verb == null ? opens : _withAction(opens, verb);
  }

  /// [body] with [verb] beside it, outside the body's own semantics: the
  /// verb is a control, and a node that silences its subtree would take it
  /// out of the tree.
  static Widget _withAction(Widget body, ServiceOverviewRowAction verb) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: body),
      _RowActionButton(action: verb),
    ],
  );
}

/// The verb beside a row: a text button in the ink, never in the fault's tone
/// (the cure is not painted as alarming as the disease), at the 44pt floor.
class _RowActionButton extends StatelessWidget {
  const _RowActionButton({required this.action});

  final ServiceOverviewRowAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton(
      onPressed: action.onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        minimumSize: const Size(56, _doorMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        // Pinned: the desktop picks compact by itself, and compact cancels
        // `minimumSize` (44 declared, 40 measured).
        visualDensity: VisualDensity.standard,
      ),
      // The hint is annotated from INSIDE the button: a `Semantics` wrapped
      // around a button is dropped, one on its child merges into the button's
      // own node, which is where "tests Nyaa" has to be heard.
      child: Semantics(
        hint: action.hint,
        child: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.weight(FontWeight.w600),
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

/// The connection an Overview is about: the one [instanceId] names, else the
/// lens's.
///
/// An id that names no connection reads the lens, as every page that takes a
/// connection does.
ServiceInstance? _overviewConnection(
  WidgetRef ref,
  ServiceKey service,
  String? instanceId,
) {
  final lens = ref.watch(activeInstanceProvider(service));
  if (instanceId == null || instanceId.isEmpty) return lens;
  return ref.watch(
        currentSettingsProvider.select(
          (settings) => settings.instanceById(instanceId),
        ),
      ) ??
      lens;
}

/// The probe of the connection an Overview is about: [serviceSummaryProvider]
/// for the lens, which everything that reads the lens's health shares, and the
/// connection's own probe for another one.
ProviderListenable<AsyncValue<ServiceSummary>> _overviewSummary(
  WidgetRef ref,
  ServiceKey service,
  String? instanceId,
) {
  final lensId = ref.watch(activeInstanceProvider(service))?.id;
  if (instanceId == null || instanceId.isEmpty || instanceId == lensId) {
    return serviceSummaryProvider(service);
  }
  return instanceSummaryProvider((service: service, instanceId: instanceId));
}

/// Host, version, whether it is answering, and which connection you are
/// reading.
///
/// [instanceId] is the connection the page reads when that is not the lens's:
/// a visit to a media server opened on another connection. Null or empty is
/// the lens.
class ServiceOverviewIdentity extends ConsumerWidget {
  const ServiceOverviewIdentity({
    super.key,
    required this.service,
    this.instanceId,
  });

  final ServiceKey service;
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final summary = ref.watch(_overviewSummary(ref, service, instanceId));
    final instance = _overviewConnection(ref, service, instanceId);
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
          // Saved without its key: not asked, and said as not set up.
          : value.isNotSetUp
          ? ServiceConnectionStatus.notConfigured
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
              facts.join(dotSeparator),
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
///    addresses once, and its Retry knocks at both;
///  * for a lens connection that did not answer at the one address it has
///    ([ServiceFailureReason.unreachable]): the red names it once. Not for a
///    page that already says it once on its own ([ownSilence]: Stream's
///    offline state, drawn when its own reads failed).
///
/// "Lens" above is the connection the page reads: [instanceId] when the page
/// reads another (a visit to a media server opened on one), else the lens.
///
/// A spread rather than a wrapper, so the page's list keeps building its
/// sections lazily; called from the page's build with its [ref].
List<Widget> sectionsOrOneLine(
  WidgetRef ref,
  ServiceKey service,
  List<Widget> sections, {
  bool ownSilence = false,
  String? instanceId,
}) {
  final reason = ref.watch(
    _overviewSummary(
      ref,
      service,
      instanceId,
    ).select((summary) => summary.asData?.value.failureReason),
  );
  return switch (reason) {
    ServiceFailureReason.onlyAtHome => [
      ServiceOverviewOnlyAtHome(service: service, instanceId: instanceId),
    ],
    ServiceFailureReason.unreachableAtBoth => [
      ServiceOverviewUnanswered(service: service, instanceId: instanceId),
    ],
    ServiceFailureReason.unreachable when !ownSilence => [
      ServiceOverviewUnanswered.atItsAddress(
        service: service,
        instanceId: instanceId,
      ),
    ],
    _ => sections,
  };
}

/// The one line of an Overview whose lens connection did not answer. Red,
/// and its Retry (a ghost in ink) asks again (`retryDashboardServices`). See
/// [sectionsOrOneLine].
class ServiceOverviewUnanswered extends ConsumerWidget {
  /// Neither address answered: `Radarr did not answer at home or away`, then
  /// where, one address a line; its Retry asks both.
  const ServiceOverviewUnanswered({
    super.key,
    required this.service,
    this.instanceId,
  }) : _atBoth = true;

  /// The one address the connection has did not answer:
  /// `Radarr did not answer at nas.home.arpa:7878.`
  const ServiceOverviewUnanswered.atItsAddress({
    super.key,
    required this.service,
    this.instanceId,
  }) : _atBoth = false;

  final ServiceKey service;

  /// The connection that did not answer when it is not the lens's; null or
  /// empty is the lens.
  final String? instanceId;
  final bool _atBoth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = _overviewConnection(ref, service, instanceId);
    final name =
        (ref.watch(hasMultipleInstancesProvider(service)) && instance != null
            ? ref.watch(connectionNameProvider(instance.id))
            : null) ??
        service.title;
    final unanswered = instance == null || !_atBoth
        ? null
        : ref.watch(unansweredConnectionProvider(instance.id));
    final reason = _atBoth
        ? ServiceFailureReason.unreachableAtBoth
        : ServiceFailureReason.unreachable;
    // Nothing answered, so nothing in front of it did either: no gateway.
    final headline = _atBoth
        ? failureHeadline(ServiceFailureReason.unreachableAtBoth, subject: name)
        : failureHeadline(ServiceFailureReason.unreachable, subject: name);
    // The address it asked: on a connection with an address away, the one
    // its route is on.
    final host = _atBoth || instance == null
        ? null
        : service.extractHost(
            ref.watch(connectionReachProvider(instance.id))?.url,
          );
    final message = switch ((unanswered, host)) {
      (final unanswered?, _) => '$headline.\n${unanswered.failureDetail}',
      (_, final host?) when !_atBoth && host.isNotEmpty =>
        '$headline at $host.',
      _ => '$headline.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: InlineErrorRetry.flush(
        message: message,
        error: unanswered ?? ClassifiedFailure(reason),
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
  const ServiceOverviewOnlyAtHome({
    super.key,
    required this.service,
    this.instanceId,
  });

  final ServiceKey service;

  /// The connection with no address away when it is not the lens's; null or
  /// empty is the lens.
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = _overviewConnection(ref, service, instanceId);
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
