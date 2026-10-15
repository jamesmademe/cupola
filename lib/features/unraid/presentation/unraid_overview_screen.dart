import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// The first tab of Unraid's service home.
///
/// Overview alone carries the identity block and the readouts; Array and
/// Docker are each a view of one kind of record, and then three regions: the
/// array and its disks, the containers, and what the server itself says about
/// its uptime and release.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both floated above this page
/// as glass bands so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// **The readouts are here because they are nowhere else.** `UnraidScreen` used
/// to be one page carrying `ServiceKpiPeek`; splitting it into the Array and
/// Docker halves left the four readouts drawn by neither, which is correct for
/// those tabs (the Overview is the tab that carries them) and left a hole until
/// this page existed. That hole closes here.
///
/// ## Where this departs from the board, and why
///
/// VMs, Notifications and Shares now have dedicated tab screens backed by the
/// current GraphQL contract. They are intentionally not duplicated in this
/// Overview, which remains the server summary; mutation controls on those
/// tabs are shown only when the instance advertises the matching capability.
///  * **Parity**: `valid · checked 12 days ago · 0 errors` needs the parity
///    history the `array` document does not carry.
///  * **The System strip**: `CPU 12% · RAM 41% · Net 84 Mb/s` needs live
///    metrics. `info { os }` answers a distro, a release and a boot time, which
///    is what the System section below actually draws.
///
/// Fields the contract still does not provide remain absent rather than being
/// represented by invented zeroes. That distinction keeps the dashboard's
/// figures honest while the tab bar still offers complete navigation.
///
/// **Per-disk device and size are absent** (`sdc · 6 TB` on the board): the
/// `ArrayDisk` type this app queries carries `name`, `status` and `temp`, and
/// nothing else. **SMART verdicts** likewise.
///
/// **Unraid has never been run against a real instance here**, so nothing on
/// this page is inferred from a field the three committed queries do not name.
///
/// Sections load and fail independently. An Unraid answering `array` but not
/// `dockerContainers` still draws two regions, and the third says so in its own
/// slot instead of taking the page down.
class UnraidOverviewScreen extends ConsumerWidget {
  const UnraidOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

  /// The room the two glass bands above this page occupy.
  ///
  /// Composed from the same two constants the router composes its own from, so
  /// a screen built outside the router (a test, a preview) reserves the right
  /// space instead of tucking its first region under the tab bar.
  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checked **before** any provider is reached. `unraidClientProvider` throws
    // `Unraid not configured`, and letting `AsyncValueWidget` catch that throw
    // would draw the same pixels while leaving three *failed* providers behind
    // it, each scheduling a retry with backoff for a condition no amount of
    // waiting changes, which surfaces in tests as a pending timer and on
    // device as a battery cost.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.unraid),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.unraid.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to Unraid's own connection form
            // rather than the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.unraid),
      ),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        invalidateServiceReadout(ref, ServiceKey.unraid);
        // The three documents, and then the folds derived from them. The folds
        // are invalidated too rather than left to recompute: they are
        // `autoDispose`, so a region the user has scrolled past may already
        // have been collected, and invalidating only the source would leave it
        // holding the previous fold when it came back.
        ref.invalidate(unraidArrayProvider);
        ref.invalidate(unraidDockerProvider);
        ref.invalidate(unraidInfoProvider);
        ref.invalidate(unraidOverviewArrayProvider);
        ref.invalidate(unraidOverviewDockerProvider);
        ref.invalidate(unraidOverviewSystemProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not three independently scrolling panes.
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const ServiceOverviewIdentity(service: ServiceKey.unraid),
          ...sectionsOrOnlyAtHome(ref, ServiceKey.unraid, [
            ServiceKpiPeek(
              kpis: ref.watch(serviceKpiProvider(ServiceKey.unraid)),
              accent: ServiceKey.unraid.accent,
            ),
            // The order the mobile board keeps once the regions with no read
            // layer fall away: the array, then the containers. System comes
            // last because it is the only region nobody opens the app to check.
            const _ArraySection(),
            const _DockerSection(),
            const _SystemSection(),
          ]),
        ],
      ),
    );
  }
}

// ─── 1. Array ───────────────────────────────────────────────────────────────

/// The array, its capacity, and the slots that make it up.
class _ArraySection extends ConsumerWidget {
  const _ArraySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digest = ref.watch(unraidOverviewArrayProvider);
    final data = digest.asData?.value;
    // `—` while the document is in flight, after it failed, and also when it
    // answered with nothing this header could state. A `0 disks` printed over
    // an unanswered question is a claim nobody made, and the claim it makes:
    // "there is no array" is the one a user would act on.
    final headline = data?.headline ?? '';

    return ServiceOverviewSection(
      service: ServiceKey.unraid,
      title: 'Array',
      subtitle: headline.isEmpty ? '—' : headline,
      destination: ServiceTab.array,
      child: AsyncValueWidget<UnraidArrayDigest>.section(
        value: digest,
        service: ServiceKey.unraid,
        consequence: 'the array is not shown',
        loadingLabel: 'Loading the array',
        onRetry: () {
          ref.invalidate(unraidOverviewArrayProvider);
          ref.invalidate(unraidArrayProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (value) => value.preview.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.storage_rounded,
          label: 'No disks reported',
        ),
        data: (value) => Column(
          children: [for (final disk in value.preview) _DiskRow(disk: disk)],
        ),
      ),
    );
  }
}

class _DiskRow extends StatelessWidget {
  const _DiskRow({required this.disk});

  final UnraidDisk disk;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.warning`: the walk resolves
    // amber against the surface this row actually lands on, which on the light
    // theme is a different hue from the one the dark artboards draw. A drive
    // over the warning threshold, or a slot the array has flagged, is a
    // **fault** and therefore amber. Nothing on this page is ever red, because
    // red means the host did not answer, and a disk it told us about is proof
    // that it did.
    final tone = statusToneColor(
      colorScheme,
      disk.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: unraidDiskSpoken(disk),
      // A dot, not a glyph: every row here is a disk, and a second picture per
      // row would say they are different kinds of thing.
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      title: disk.name,
      // Unraid's own token (`DISK_OK`, `DISK_DSBL`), exactly as the Array tab
      // prints it. Translating it into friendlier words here would give one
      // service two vocabularies for one field, two taps apart.
      detail: disk.status,
      // `spun down` in the figure's place, never `0 °C` and never an em dash:
      // we know precisely why there is no reading, and saying so is the rule
      // the Array tab already states.
      trailing: unraidDiskReading(disk),
    );
  }
}

// ─── 2. Docker ──────────────────────────────────────────────────────────────

/// What is running on the server, faults first.
class _DockerSection extends ConsumerWidget {
  const _DockerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digest = ref.watch(unraidOverviewDockerProvider);
    final data = digest.asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.unraid,
      title: 'Docker',
      // The **census**, not the length of the preview below it. Five rows over
      // forty containers would otherwise print "5 containers" and report the
      // other thirty-five nowhere; `dockerContainers` is not paged, so the
      // total this states is the whole population the rows are drawn from.
      subtitle: data == null ? '—' : data.headline,
      destination: ServiceTab.docker,
      child: AsyncValueWidget<UnraidDockerDigest>.section(
        value: digest,
        service: ServiceKey.unraid,
        consequence: 'its containers are not shown',
        loadingLabel: 'Loading the containers',
        onRetry: () {
          ref.invalidate(unraidOverviewDockerProvider);
          ref.invalidate(unraidDockerProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (value) => value.preview.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.widgets_outlined,
          label: 'No containers reported',
        ),
        data: (value) => Column(
          children: [
            for (final container in value.preview)
              _ContainerRow(container: container),
          ],
        ),
      ),
    );
  }
}

class _ContainerRow extends StatelessWidget {
  const _ContainerRow({required this.container});

  final UnraidDockerContainer container;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Five arms, one row: green for a container that is up and whose
    // healthcheck agrees, amber for the faults, neutral for every deliberate
    // state: stopped, paused, never started. A container the user stopped is
    // **backlog**, and painting it amber beside one the kernel killed is how
    // the tone rule gets broken in a Docker list.
    final tone = statusToneColor(
      colorScheme,
      container.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: '${container.name}, ${container.summary}',
      // A dot rather than the Docker tab's per-condition glyph set. The words
      // under the name already name the condition ("exited unexpectedly ·
      // exit 137 · 3 hours ago"), and a second copy of that glyph map living
      // here is a second copy that would drift from the first.
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      // The name stays in ink: the tone belongs to the dot, and a page where
      // every title is coloured has no way left to say one of them is
      // different.
      title: container.name,
      detail: container.summary,
    );
  }
}

// ─── 3. System ──────────────────────────────────────────────────────────────

/// What the server says about itself.
class _SystemSection extends ConsumerWidget {
  const _SystemSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = ref.watch(unraidOverviewSystemProvider);

    return ServiceOverviewSection(
      service: ServiceKey.unraid,
      title: 'System',
      // No CPU, RAM or network figure, which the board's System region draws:
      // `info { os { distro release uptime } }` is the whole document, and
      // there is no metrics call to add one. Deleting the promise beats drawing
      // three meters that would read zero forever.
      //
      // No link either. Unraid's bar is Overview, Array, Docker, VMs,
      // Notifications and Shares, and there is no System tab to send anyone to.
      child: AsyncValueWidget<List<UnraidSystemFact>>.section(
        value: facts,
        service: ServiceKey.unraid,
        consequence: 'its uptime and release are not shown',
        loadingLabel: 'Loading the system',
        onRetry: () {
          ref.invalidate(unraidOverviewSystemProvider);
          ref.invalidate(unraidInfoProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        // Never empty: `info` either answers both facts (with `—` for one it
        // left out), or it fails, and a failure is the error state rather than
        // an empty one.
        data: (data) =>
            Column(children: [for (final fact in data) _SystemRow(fact: fact)]),
      ),
    );
  }
}

class _SystemRow extends StatelessWidget {
  const _SystemRow({required this.fact});

  final UnraidSystemFact fact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ServiceOverviewRow(
      spoken: fact.spoken,
      leading: Icon(fact.icon, size: 18, color: colorScheme.onSurfaceVariant),
      // The figure in the title slot and its label beneath: the inverse of the
      // two regions above, and deliberately so. There the title is the subject
      // (a disk, a container) and the reading is secondary, which is the shape
      // `ServiceOverviewRow` was built for. System has no subject: "Uptime" is
      // chrome and "18 days" is the content, so putting the label first would
      // print the caption at full ink and dim the answer to 11pt at the right
      // margin.
      title: fact.value,
      detail: fact.label,
    );
  }
}
