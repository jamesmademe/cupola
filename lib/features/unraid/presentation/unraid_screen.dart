import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_capability.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// Which half of the old Unraid dashboard a page lists.
///
/// Public since the tab model: Array and Docker are two entries on Unraid's own
/// bar now, so the choice is made by the router rather than by scrolling past
/// one section to reach the other.
enum UnraidSection {
  array('Array'),
  docker('Docker'),
  vms('VMs'),
  notifications('Notifications'),
  shares('Shares');

  const UnraidSection(this.label);

  /// The word the app bar prints when this page draws one of its own.
  final String label;
}

/// One section of Unraid — the array's disks, or the Docker containers.
///
/// **It used to be both**, one under the other on a single page at
/// `/dashboard/unraid`. Unraid's bar draws them as separate destinations, so
/// the page split; the two halves still read the same two documents, and each
/// tab asks only for the one it draws.
///
/// Named constructors rather than a `section:` argument or a boolean, following
/// `lib/core/widgets/AGENTS.md`: a call site says which half it wants in the
/// constructor name, and there is no third value to handle.
///
/// The readouts are **not** here. `ServiceKpiPeek` sat on the single page
/// because the single page was the service; under the tab model the Overview is
/// the tab that carries the identity block and the readouts, and repeating them
/// on a section tab would be the same four figures twice in one scroll.
///
/// **Two pages write; Array, Docker and Shares only read.** The contract this
/// app is written against (`test/fixtures/unraid/schema.graphql`) declares two
/// mutations Cupola uses — `vm { start stop resume … }` and
/// `archiveNotification` — and those are the VMs and Notifications writes,
/// each gated on the key's scope (`unraid_capability.dart`). Container writes
/// stay absent on purpose: decision 14 draws Stop and Restart a container, but
/// the contract declares no container mutation, and guessing a name would ship
/// a confirm dialog that names the user's server and then fails, which is
/// worse than not offering it. See the notes on
/// `UnraidDockerContainer.condition` for the half that *is* readable from what
/// the API already returns.
class UnraidScreen extends ConsumerWidget {
  /// The array half — Unraid's Array tab.
  const UnraidScreen.array({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = UnraidSection.array;

  /// The container half — Unraid's Docker tab.
  const UnraidScreen.docker({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = UnraidSection.docker;

  const UnraidScreen.vms({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = UnraidSection.vms;

  const UnraidScreen.notifications({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = UnraidSection.notifications;

  const UnraidScreen.shares({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : section = UnraidSection.shares;

  final UnraidSection section;

  /// Whether to draw this screen's own app bar.
  ///
  /// False inside the tab shell, where `ServiceHomeScreen` draws the service
  /// band and `ServiceTabScaffold` the tab bar above it: a third bar of its own
  /// would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    // Checked **before** any provider is read, not after: `unraidClientProvider`
    // throws when Unraid is not configured, and a `FutureProvider` that throws
    // is a failed provider — it schedules a retry with backoff for a condition
    // no waiting changes, and surfaces in tests as a pending timer.
    final isConfigured = settings.isServiceConfigured(ServiceKey.unraid);

    return AmbientScaffold(
      accent: ServiceKey.unraid.accent,
      appBar: showAppBar ? GlassAppBar(title: Text(section.label)) : null,
      body: SafeArea(
        top: showAppBar,
        // The shared placeholder, not a private copy: four dashboards had each
        // grown their own "this service isn't set up" card, which is the state
        // `NotConfiguredPlaceholder` exists to unify.
        child: isConfigured
            // Keyed by section so the five cannot share one list state:
            // each is a separate branch of the service shell and keeps its own
            // scroll offset.
            ? _UnraidSection(
                key: ValueKey(section),
                section: section,
                topPadding: topPadding,
              )
            : NotConfiguredPlaceholder.forService(ServiceKey.unraid),
      ),
    );
  }
}

class _UnraidSection extends ConsumerWidget {
  const _UnraidSection({
    super.key,
    required this.section,
    required this.topPadding,
  });

  final UnraidSection section;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.unraid));
    // A failed probe, in its own words: "did not answer" only when nothing did,
    // the refusal and its remedy when the key was refused.
    final failed = summaryAsync.whenOrNull(
      data: (summary) => summary.isOnline ? null : summary,
    );

    if (failed != null) {
      return ServiceOfflineState.fromSummary(
        summary: failed,
        onRetry: () => _invalidate(ref, section),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidate(ref, section);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: topPadding,
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: switch (section) {
          UnraidSection.array => [
            const SectionHeader(title: 'Array disks', showChevron: false),
            const SizedBox(height: 2),
            _DiskList(arrayAsync: ref.watch(unraidArrayProvider)),
          ],
          UnraidSection.docker => _dockerChildren(
            ref.watch(unraidDockerProvider),
          ),
          UnraidSection.vms => [
            CapabilityBannerSlot(
              connectionId: capabilityConnectionId(ref, ServiceKey.unraid),
              copy: unraidVmsCopy,
              resources: {UnraidResource.vms.name},
            ),
            const SectionHeader(title: 'Virtual machines', showChevron: false),
            const SizedBox(height: 2),
            _VmList(vmsAsync: ref.watch(unraidVmsProvider)),
          ],
          UnraidSection.notifications => [
            CapabilityBannerSlot(
              connectionId: capabilityConnectionId(ref, ServiceKey.unraid),
              copy: unraidNotificationsCopy,
              resources: {UnraidResource.notifications.name},
            ),
            const SectionHeader(
              title: 'Unread notifications',
              showChevron: false,
            ),
            const SizedBox(height: 2),
            _NotificationList(
              notificationsAsync: ref.watch(unraidNotificationsProvider),
            ),
          ],
          UnraidSection.shares => [
            const SectionHeader(title: 'Shares', showChevron: false),
            const SizedBox(height: 2),
            _ShareList(sharesAsync: ref.watch(unraidSharesProvider)),
          ],
        },
      ),
    );
  }

  List<Widget> _dockerChildren(
    AsyncValue<List<UnraidDockerContainer>> dockerAsync,
  ) => [
    SectionHeader(
      title: 'Containers',
      showChevron: false,
      // The board heads this section with "14 containers · 12 running ·
      // 1 stopped · 1 unhealthy". Only the arms the payload can answer
      // are printed, and none of them before the load resolves: a header
      // reading "0 running" while the request is still in flight states
      // the one thing we do not yet know.
      subtitle: dockerAsync.asData == null
          ? null
          : _dockerTally(dockerAsync.requireValue),
    ),
    const SizedBox(height: 2),
    _DockerList(dockerAsync: dockerAsync),
  ];
}

/// `14 containers · 12 running · 1 unhealthy` — only the arms that are non-zero.
///
/// A tally that printed every arm would read "0 unhealthy" on a healthy server,
/// which is a sentence about a problem where there is none.
String _dockerTally(List<UnraidDockerContainer> containers) {
  int count(UnraidContainerCondition condition) =>
      containers.where((c) => c.condition == condition).length;

  final running = count(UnraidContainerCondition.running);
  final unhealthy = count(UnraidContainerCondition.unhealthy);
  final stopped = count(UnraidContainerCondition.stopped);
  final crashed =
      count(UnraidContainerCondition.exitedUnexpectedly) +
      count(UnraidContainerCondition.restarting) +
      count(UnraidContainerCondition.dead);

  return [
    '${containers.length} containers',
    if (running > 0) '$running running',
    if (stopped > 0) '$stopped stopped',
    if (unhealthy > 0) '$unhealthy unhealthy',
    if (crashed > 0) '$crashed failed',
  ].join(' · ');
}

/// Re-reads what the tab on screen draws, and nothing else.
///
/// A pull on Array no longer re-fetches the container list: the two are
/// separate branches now, and refreshing a page the user cannot see is a round
/// trip they did not ask for. The KPI and summary providers are shared and are
/// invalidated by both, because both are what the Dashboard card reads.
void _invalidate(WidgetRef ref, UnraidSection section) {
  // A refresh is the moment to find out the key was given permissions it did
  // not have when the page opened, on every section that has writes and on
  // Shares, whose writes are the next to land.
  void recheck() => recheckCapability(
    ref,
    ref.read(activeInstanceProvider(ServiceKey.unraid))?.id ?? '',
  );
  switch (section) {
    case UnraidSection.array:
      ref.invalidate(unraidArrayProvider);
    case UnraidSection.docker:
      ref.invalidate(unraidDockerProvider);
    case UnraidSection.vms:
      ref.invalidate(unraidVmsProvider);
      recheck();
    case UnraidSection.notifications:
      ref.invalidate(unraidNotificationsProvider);
      recheck();
    case UnraidSection.shares:
      ref.invalidate(unraidSharesProvider);
      recheck();
  }
  ref.invalidate(serviceKpiProvider(ServiceKey.unraid));
  ref.invalidate(serviceSummaryProvider(ServiceKey.unraid));
}

class _VmList extends ConsumerWidget {
  const _VmList({required this.vmsAsync});
  final AsyncValue<List<UnraidVm>> vmsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) => vmsAsync.when(
    data: (vms) => vms.isEmpty
        ? const _UnraidEmpty(message: 'No virtual machines reported.')
        : Column(
            children: vms.map((vm) => _VmTile(vm: vm)).toList(growable: false),
          ),
    loading: () => const ListRowsShimmer(count: 3),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.unraid,
        error,
        consequence: 'its virtual machines are not shown',
      ),
      error: error,
      onRetry: () => ref.invalidate(unraidVmsProvider),
    ),
  );
}

class _VmTile extends ConsumerWidget {
  const _VmTile({required this.vm});
  final UnraidVm vm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = statusToneColor(
      Theme.of(context).colorScheme,
      vm.tone,
      surface: Theme.of(context).colorScheme.surface,
    );
    final action = vm.isRunning
        ? UnraidVmAction.stop
        : (vm.isPaused ? UnraidVmAction.resume : UnraidVmAction.start);
    final connectionId = capabilityConnectionId(ref, ServiceKey.unraid);
    return _UnraidTile(
      icon: Icons.computer_rounded,
      iconColor: color,
      title: vm.name,
      // `PMSUSPENDED` and `SHUTOFF` are libvirt's words, not anyone else's.
      detail: _vmStateLabel(vm.state),
      trailing: CapabilityGatedAction.icon(
        service: ServiceKey.unraid,
        connectionId: connectionId,
        resource: UnraidResource.vms.name,
        hint: unraidVmsCopy.hint,
        blockedMessage: 'This Unraid key can\'t start or stop VMs.',
        // `_actionVerb`, not `action.graphQl`: the mutation's field name is a
        // wire detail and "forceStop Kodi" is not a sentence.
        tooltip: '${_actionVerb(action)} ${vm.name}',
        onTap: () => _run(context, ref, action, connectionId),
        icon: Icon(
          action == UnraidVmAction.start || action == UnraidVmAction.resume
              ? Icons.play_arrow_rounded
              : Icons.stop_rounded,
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    UnraidVmAction action,
    String connectionId,
  ) async {
    // The scope is gated at the tap (`CapabilityGatedAction.icon`), before the
    // confirmation below is ever drawn.
    if (action == UnraidVmAction.stop) {
      final host =
          ref
              .read(serviceSummaryProvider(ServiceKey.unraid))
              .asData
              ?.value
              .host ??
          'this Unraid host';
      // The shared confirmation, not a hand-built `AlertDialog`: the same
      // title row, neutral button and verb-first label as every other one.
      final result = await showAppConfirmDialog(
        context: context,
        title: 'Stop ${vm.name}?',
        message: 'This stops the VM on $host.',
        confirmLabel: 'Stop VM',
      );
      if (!result.confirmed || !context.mounted) return;
    }
    try {
      // **The boolean is the answer, not the absence of a throw.** Unraid
      // answers 200 with `{"vm":{"stop":false}}` when it ran the mutation and
      // refused it — the VM is already stopping, libvirt is busy, the key has
      // a privilege the coarse capability check cannot see. Ignoring it
      // refreshed the list and told the user nothing, which reads exactly like
      // a tap that did not register.
      final accepted = await ref
          .read(unraidClientProvider)
          .runVmAction(vm.id, action);
      ref.invalidate(unraidVmsProvider);
      if (accepted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${vm.name} did not accept ${_actionVerb(action)}. '
            'It may already be changing state.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      // A `FORBIDDEN` is the key answering the question the probe asked: it
      // marks the connection read-only and says so, rather than reading as a
      // failure.
      if (reportCapabilityRefusal(
        context,
        ref,
        CapabilityTarget(connectionId: connectionId, copy: unraidVmsCopy),
        error,
      )) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('VM action failed: $error')));
    }
  }
}

/// A libvirt domain state as a reader would say it.
///
/// Unknown states fall back to the lower-cased wire value rather than to a
/// guess: a state this app has not been taught is still better shown than
/// hidden behind "unknown".
String _vmStateLabel(String state) => switch (state.toUpperCase()) {
  'RUNNING' => 'running',
  'PAUSED' => 'paused',
  'SHUTOFF' || 'SHUTDOWN' => 'stopped',
  'CRASHED' => 'crashed',
  'PMSUSPENDED' => 'suspended',
  'IDLE' => 'idle',
  'NOSTATE' => 'state unknown',
  _ => state.toLowerCase(),
};

/// The action as a user would name it, rather than as GraphQL spells it.
String _actionVerb(UnraidVmAction action) => switch (action) {
  UnraidVmAction.start => 'start',
  UnraidVmAction.stop => 'stop',
  UnraidVmAction.pause => 'pause',
  UnraidVmAction.resume => 'resume',
  UnraidVmAction.forceStop => 'force stop',
  UnraidVmAction.reboot => 'reboot',
};

class _NotificationList extends ConsumerWidget {
  const _NotificationList({required this.notificationsAsync});
  final AsyncValue<UnraidNotifications> notificationsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) => notificationsAsync.when(
    data: (value) => value.items.isEmpty
        ? const _UnraidEmpty(message: 'No unread notifications.')
        : Column(
            children: value.items
                .map((item) => _NotificationTile(item: item))
                .toList(growable: false),
          ),
    loading: () => const ListRowsShimmer(count: 4),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.unraid,
        error,
        consequence: 'its notifications are not shown',
      ),
      error: error,
      onRetry: () => ref.invalidate(unraidNotificationsProvider),
    ),
  );
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});
  final UnraidNotification item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = statusToneColor(
      Theme.of(context).colorScheme,
      item.tone,
      surface: Theme.of(context).colorScheme.surface,
    );
    final connectionId = capabilityConnectionId(ref, ServiceKey.unraid);
    return _UnraidTile(
      icon: Icons.notifications_outlined,
      iconColor: color,
      title: item.title.isEmpty ? item.subject : item.title,
      detail: item.description.isEmpty ? item.subject : item.description,
      trailing: CapabilityGatedAction.icon(
        service: ServiceKey.unraid,
        connectionId: connectionId,
        resource: UnraidResource.notifications.name,
        hint: unraidNotificationsCopy.hint,
        blockedMessage: 'This Unraid key can\'t archive notifications.',
        tooltip: 'Archive notification',
        onTap: () async {
          try {
            await ref.read(unraidClientProvider).archiveNotification(item.id);
            ref.invalidate(unraidNotificationsProvider);
          } catch (error) {
            if (!context.mounted) return;
            if (reportCapabilityRefusal(
              context,
              ref,
              CapabilityTarget(
                connectionId: connectionId,
                copy: unraidNotificationsCopy,
              ),
              error,
            )) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not archive: $error')),
            );
          }
        },
        icon: const Icon(Icons.archive_outlined),
      ),
    );
  }
}

class _ShareList extends ConsumerWidget {
  const _ShareList({required this.sharesAsync});
  final AsyncValue<List<UnraidShare>> sharesAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) => sharesAsync.when(
    data: (shares) => shares.isEmpty
        ? const _UnraidEmpty(message: 'No shares reported.')
        : Column(
            children: shares
                .map((share) {
                  final used = share.usedFraction == null
                      ? '—'
                      : '${(share.usedFraction! * 100).round()}% used';
                  final detail = [
                    used,
                    if (share.cached != null)
                      share.cached! ? 'cached' : 'array',
                    if (share.comment.isNotEmpty) share.comment,
                  ].join(' · ');
                  return _UnraidTile(
                    icon: Icons.folder_outlined,
                    // The accent walked for contrast against the surface it
                    // lands on, not the raw brand orange: Unraid's is one of
                    // the seven that fails the check on a light ground.
                    iconColor: ServiceTheme.onTint(
                      ServiceKey.unraid.accent,
                      surface: Theme.of(context).colorScheme.surface,
                      tintAlpha: 0,
                    ),
                    title: share.name,
                    detail: detail,
                  );
                })
                .toList(growable: false),
          ),
    loading: () => const ListRowsShimmer(count: 4),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.unraid,
        error,
        consequence: 'its shares are not shown',
      ),
      error: error,
      onRetry: () => ref.invalidate(unraidSharesProvider),
    ),
  );
}

class _UnraidEmpty extends StatelessWidget {
  const _UnraidEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Text(message),
  );
}

class _UnraidTile extends StatelessWidget {
  const _UnraidTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.detail,
    this.trailing,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String detail;
  final Widget? trailing;

  // One sentence for the row, and the parts it is made of silenced — but only
  // the parts, not the trailing control. `ExcludeSemantics` around the whole
  // `ListTile` would take the Archive and start/stop buttons with it, and a
  // bare `container: true` leaves the title and detail as their own stops, so
  // the row read as three. The icon, title and subtitle are excluded
  // individually; `trailing` stays outside that and keeps its own node.
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    label: '$title, $detail',
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusMd,
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        leading: ExcludeSemantics(child: Icon(icon, color: iconColor)),
        title: ExcludeSemantics(child: Text(title)),
        subtitle: ExcludeSemantics(
          child: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        trailing: trailing,
      ),
    ),
  );
}

class _DiskList extends ConsumerWidget {
  const _DiskList({required this.arrayAsync});

  final AsyncValue<UnraidArray> arrayAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return arrayAsync.when(
      data: (array) {
        if (array.disks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No array disks reported.'),
          );
        }
        return Column(
          children: array.disks.map((disk) => _DiskTile(disk: disk)).toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.unraid,
          error,
          consequence: 'the array is not shown',
        ),
        error: error,
        onRetry: () => ref.invalidate(unraidArrayProvider),
      ),
    );
  }
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({required this.disk});

  final UnraidDisk disk;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // A slot with no temperature is spun down, not cold. It used to render as
    // no reading at all, which left the row silent about the one thing that
    // explains a missing figure.
    final tempLabel = disk.spunDown ? 'spun down' : '${disk.temp}°C';
    final tone = statusToneColor(
      colorScheme,
      disk.tone,
      // The reading sits on the row's own card, not on the page background;
      // walking against the wrong ground is how amber ends up under 3:1 on the
      // light theme.
      surface: colorScheme.surface,
    );
    // The plate is a 12% accent wash, so its glyph is ink on that composite
    // rather than on the surface — seven of the seventeen accents lose the
    // contrast check otherwise, and Unraid's orange is one of them.
    final plateInk = ServiceTheme.onTint(
      ServiceKey.unraid.accent,
      surface: colorScheme.surface,
      tintAlpha: 0.12,
    );

    return Semantics(
      container: true,
      // Three fragments — a device name, a `DISK_OK` token and a bare numeral —
      // read as three unrelated stops. One sentence, in the order a person
      // would say it, with the unit spoken rather than glyphed.
      label: [
        disk.name,
        if (disk.status.isNotEmpty) disk.status,
        disk.spunDown ? 'spun down' : '${disk.temp} degrees',
      ].join(', '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Material(
            color: colorScheme.surface,
            borderRadius: AppRadius.borderRadiusMd,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: AppRadius.borderRadiusMd,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: ServiceKey.unraid.accent.withValues(alpha: 0.12),
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.storage_rounded,
                      size: 16,
                      color: plateInk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          disk.name,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium!.weight(FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (disk.status.isNotEmpty)
                          Text(
                            disk.status,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: disk.tone == StatusTone.warning
                                      ? tone
                                      : colorScheme.onSurfaceVariant,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    tempLabel,
                    style: Theme.of(context).textTheme.labelMedium!
                        .weight(FontWeight.w600)
                        .tabular
                        .copyWith(
                          color: disk.warm
                              ? tone
                              : colorScheme.onSurfaceVariant,
                        ),
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

class _DockerList extends ConsumerWidget {
  const _DockerList({required this.dockerAsync});

  final AsyncValue<List<UnraidDockerContainer>> dockerAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return dockerAsync.when(
      data: (containers) {
        if (containers.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No containers reported.'),
          );
        }
        final sorted = [
          ...containers,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return Column(
          children: sorted
              .map((container) => _ContainerTile(container: container))
              .toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.unraid,
          error,
          consequence: 'its containers are not shown',
        ),
        error: error,
        onRetry: () => ref.invalidate(unraidDockerProvider),
      ),
    );
  }
}

class _ContainerTile extends StatelessWidget {
  const _ContainerTile({required this.container});

  final UnraidDockerContainer container;

  /// One glyph per condition, read off the condition rather than off the tone.
  ///
  /// A tone-keyed icon can only answer one picture for the four amber states,
  /// and "unhealthy while up" and "OOM-killed an hour ago" are not the same
  /// picture — the first is a warning about something running, the second is a
  /// thing that is down.
  IconData get _glyph => switch (container.condition) {
    UnraidContainerCondition.running => Icons.play_circle_rounded,
    UnraidContainerCondition.unhealthy => Icons.monitor_heart_rounded,
    UnraidContainerCondition.paused => Icons.pause_circle_rounded,
    UnraidContainerCondition.stopped => Icons.stop_circle_rounded,
    UnraidContainerCondition.exitedUnexpectedly ||
    UnraidContainerCondition.dead => Icons.error_outline_rounded,
    UnraidContainerCondition.restarting => Icons.sync_problem_rounded,
    UnraidContainerCondition.created => Icons.schedule_rounded,
    UnraidContainerCondition.unknown => Icons.help_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Decision 15 in one line: green for up and healthy, amber for a fault the
    // server told us about, neutral for a stop somebody chose. The tone comes
    // from the parsed condition — the row used to paint everything that was not
    // `running` in the dim foreground, so an OOM kill and a deliberate stop
    // were the same colour and the same words.
    final tone = statusToneColor(
      colorScheme,
      container.tone,
      surface: colorScheme.surface,
    );
    final neutral = container.tone == StatusTone.neutral;

    return Semantics(
      container: true,
      label: '${container.name}, ${container.summary}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Material(
            color: colorScheme.surface,
            borderRadius: AppRadius.borderRadiusMd,
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: AppRadius.borderRadiusMd,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: AppRadius.borderRadiusSm,
                    ),
                    alignment: Alignment.center,
                    child: Icon(_glyph, size: 16, color: tone),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          container.name,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium!.weight(FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          container.summary,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                // A deliberate stop says so in the ordinary
                                // metadata voice; only a fault borrows the
                                // tone, so amber on this screen always means
                                // something to look at.
                                color: neutral
                                    ? colorScheme.onSurfaceVariant
                                    : tone,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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
