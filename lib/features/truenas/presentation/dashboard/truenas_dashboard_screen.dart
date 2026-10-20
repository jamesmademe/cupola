import 'package:flutter/material.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/models/truenas_models.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/charts/radial_gauge.dart';
import 'package:cupola/features/truenas/presentation/widgets/charts/sparkline.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

/// Live metrics for the dashboard: the CPU/memory gauges and the network
/// sparkline, all derived from the newest reporting samples.
class TrueNasDashboardMetrics {
  final TrueNasReportingGraph? cpu;
  final TrueNasReportingGraph? memory;

  /// The ZFS ARC size (`arcsize`), which the kernel does not count as
  /// available memory.
  final TrueNasReportingGraph? arc;
  final TrueNasReportingGraph? network;

  /// The network sparkline series, derived once per fetch. Deriving it in the
  /// widget re-walked every sample on every rebuild, and the dashboard
  /// rebuilds on a timer.
  final List<double> networkSeries;

  /// Whether the reporting RPC answered. A successful response with no
  /// matching graph is still an answer; a transport failure is not.
  final bool answered;

  const TrueNasDashboardMetrics({
    this.cpu,
    this.memory,
    this.arc,
    this.network,
    this.networkSeries = const [],
    this.answered = true,
  });

  /// CPU busy fraction from the newest sample.
  ///
  /// TrueNAS 25.04 and later chart `truenas_cpu_usage.cpu`: a `cpu` series for
  /// the whole machine and one `cpuN` per core, each already a busy
  /// percentage (idle and iowait left out). 24.10 charts netdata's
  /// `system.cpu` by CPU state, read as one minus the idle share.
  double? get cpuUsage =>
      _aggregateCpu(cpu) ?? _busyFraction(cpu, idleLabel: 'idle');

  /// The fraction of [totalBytes] (the `physmem` of `system.info`) that
  /// services use, from the newest samples.
  ///
  /// TrueNAS 25.04 and later chart `truenas_meminfo.available` (the kernel's
  /// `MemAvailable`, one `available` series in bytes) and `arcsize`. The ZFS
  /// ARC is not in `MemAvailable` and grows into whatever RAM is idle, so
  /// `total - available` reads near full on any healthy NAS. Services are
  /// `total - available - arc`, the figure the TrueNAS dashboard's own memory
  /// widget calls Services. A chart split by state with a `used` series is
  /// read as its share.
  double? memoryUsage({int? totalBytes}) {
    if (memoryBreakdown(totalBytes: totalBytes) case final split?) {
      return split.usedFraction;
    }
    final available = _available;
    if (available != null && totalBytes != null && totalBytes > 0) {
      return (1 - available / totalBytes).clamp(0, 1).toDouble();
    }
    return _fractionOf(memory, matching: 'used');
  }

  /// Where [totalBytes] of memory are, from the newest samples: the split the
  /// TrueNAS dashboard's memory widget draws. Null unless both the
  /// `available` and the ARC series answered.
  TrueNasMemoryBreakdown? memoryBreakdown({int? totalBytes}) {
    final available = _available;
    final arcBytes = _newest(arc, 'size');
    if (available == null ||
        arcBytes == null ||
        totalBytes == null ||
        totalBytes <= 0) {
      return null;
    }
    final free = available.round().clamp(0, totalBytes);
    final zfsCache = arcBytes.round().clamp(0, totalBytes - free);
    return TrueNasMemoryBreakdown(
      total: totalBytes,
      services: totalBytes - free - zfsCache,
      zfsCache: zfsCache,
      free: free,
    );
  }

  /// The newest `available` sample. No machine has nothing available: a zero
  /// is a gap netdata filled in, and reads as no answer.
  double? get _available {
    final available = _newest(memory, 'available');
    return available != null && available > 0 ? available : null;
  }

  /// The machine-wide busy fraction of a per-core usage chart: its `cpu`
  /// series, or the mean of its `cpuN` series when the aggregate is missing.
  static double? _aggregateCpu(TrueNasReportingGraph? g) {
    final whole = _newest(g, 'cpu');
    if (whole != null) return (whole / 100).clamp(0, 1).toDouble();
    if (g == null || g.data.isEmpty) return null;
    final last = g.data.last;
    final labels = g.seriesLabels;
    final cores = <double>[
      for (var i = 0; i < labels.length; i++)
        if (_coreLabel.hasMatch(labels[i].toLowerCase()) &&
            (i + 1) < last.length &&
            last[i + 1] != null)
          last[i + 1]!,
    ];
    if (cores.isEmpty) return null;
    final mean = cores.reduce((a, b) => a + b) / cores.length;
    return (mean / 100).clamp(0, 1).toDouble();
  }

  static final _coreLabel = RegExp(r'^cpu\d+$');

  /// The newest value of the series labelled exactly [label], or null when
  /// the graph has no such series or no samples.
  static double? _newest(TrueNasReportingGraph? g, String label) {
    if (g == null || g.data.isEmpty) return null;
    final labels = g.seriesLabels;
    for (var i = 0; i < labels.length; i++) {
      if (labels[i].toLowerCase() != label) continue;
      final last = g.data.last;
      return (i + 1) < last.length ? last[i + 1] : null;
    }
    return null;
  }

  static double? _busyFraction(
    TrueNasReportingGraph? g, {
    required String idleLabel,
  }) {
    final idle = _fractionOf(g, matching: idleLabel);
    return idle == null ? null : (1 - idle).clamp(0, 1).toDouble();
  }

  /// Fraction of the newest sample carried by the series whose label contains
  /// [matching], or null when **no** series matches.
  ///
  /// Answering null rather than a number is the whole point. Netdata's
  /// `system.cpu` chart is a stacked percentage that *excludes* idle, so with
  /// no `idle` dimension the old arithmetic returned `total/total`, a flat
  /// 100% CPU on a completely idle box, and non-null, so the load-per-core
  /// fallback never got a chance to run. The memory side had the mirror bug:
  /// no `used` dimension meant `0/total`, a confident 0%. A metric we cannot
  /// compute has to say so.
  static double? _fractionOf(
    TrueNasReportingGraph? g, {
    required String matching,
  }) {
    if (g == null || g.data.isEmpty) return null;
    final last = g.data.last;
    final labels = g.seriesLabels;
    double total = 0;
    double matched = 0;
    var sawMatch = false;
    for (var i = 0; i < labels.length; i++) {
      final v = (i + 1) < last.length ? (last[i + 1] ?? 0) : 0;
      total += v;
      if (labels[i].toLowerCase().contains(matching)) {
        matched += v;
        sawMatch = true;
      }
    }
    if (!sawMatch || total <= 0) return null;
    return (matched / total).clamp(0, 1).toDouble();
  }
}

/// The machine's memory split three ways, in bytes, summing to [total].
class TrueNasMemoryBreakdown {
  final int total;

  /// What the system and its apps hold: neither free nor ZFS cache.
  final int services;

  /// The ZFS ARC, which gives memory back when something else needs it.
  final int zfsCache;
  final int free;

  const TrueNasMemoryBreakdown({
    required this.total,
    required this.services,
    required this.zfsCache,
    required this.free,
  });

  /// The share of [total] in use: services, without the cache.
  double get usedFraction => services / total;
}

/// Network interfaces. Split off the live metrics because addresses change on
/// a human timescale, not a 3-second one. This rides the slow refresh tick.
final truenasDashboardInterfacesProvider = FutureProvider.autoDispose((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasNetworkApiProvider).getInterfaces();
}, retry: noProviderRetry);

/// Fetches the reporting graphs behind the gauges and the sparkline.
///
/// Best-effort: if the whole call fails, or an individual graph is missing,
/// the affected metric degrades to null rather than failing the section.
final truenasDashboardMetricsProvider =
    FutureProvider.autoDispose<TrueNasDashboardMetrics>((ref) async {
      ref.watch(truenasClientProvider);
      final reporting = ref.watch(truenasReportingApiProvider);

      // One WS round-trip for all four graphs, over the shortest window that
      // still feeds a sparkline; the gauges only ever read the last sample.
      List<TrueNasReportingGraph> graphs;
      var answered = true;
      try {
        graphs = await reporting.getLiveGraphs([
          'cpu',
          'memory',
          'arcsize',
          'interface',
        ]);
      } catch (_) {
        graphs = const [];
        answered = false;
      }

      TrueNasReportingGraph? byName(String name) {
        for (final g in graphs) {
          if (g.name.toLowerCase() == name) return g;
        }
        return null;
      }

      final network = byName('interface');
      return TrueNasDashboardMetrics(
        cpu: byName('cpu'),
        memory: byName('memory'),
        arc: byName('arcsize'),
        network: network,
        networkSeries: (network == null || network.seriesLabels.isEmpty)
            ? const []
            : network.series(0).map((p) => p.v ?? 0).toList(growable: false),
        answered: answered,
      );
    }, retry: noProviderRetry);

class TrueNasDashboardScreen extends ConsumerStatefulWidget {
  const TrueNasDashboardScreen({super.key});

  @override
  ConsumerState<TrueNasDashboardScreen> createState() =>
      _TrueNasDashboardScreenState();
}

class _TrueNasDashboardScreenState
    extends ConsumerState<TrueNasDashboardScreen> {
  /// Fast cadence for live metrics (CPU / memory / network).
  static const _liveInterval = Duration(seconds: 3);

  /// The heavier system/pools/alerts snapshot, and the interface list, which
  /// changes on a human timescale, refresh every [_slowEvery] live ticks
  /// (~15s) so they stay fresh without hammering the server.
  static const _slowEvery = 5;
  int _tick = 0;

  /// The screen owns its timer rather than a provider, because each tick is a
  /// hop on the WebSocket the TrueNAS client holds open, not a provider
  /// invalidation this page can express any other way. [GatedPollTimer] gives it
  /// the same visibility contract a gated provider gets.
  GatedPollTimer? _live;

  @override
  void dispose() {
    _live?.dispose();
    super.dispose();
  }

  void _onLiveTick() {
    ref.invalidate(truenasDashboardMetricsProvider);
    _tick++;
    if (_tick % _slowEvery == 0) {
      ref.invalidate(truenasDashboardProvider);
      ref.invalidate(truenasDashboardInterfacesProvider);
    }
  }

  void _refresh() {
    ref.invalidate(truenasDashboardProvider);
    ref.invalidate(truenasDashboardMetricsProvider);
    ref.invalidate(truenasDashboardInterfacesProvider);
  }

  @override
  Widget build(BuildContext context) {
    // The most expensive poll in the app: one `getLiveGraphs` RPC every three
    // seconds, plus two more every fifteen, over a socket that may be crossing a
    // VPN. It used to pause only while the app was backgrounded, so it went on
    // spending that from behind another tab, or under the Storage page pushed on
    // top of it, for as long as the app lived.
    (_live ??= GatedPollTimer(
      id: 'truenas.dashboard.live',
      interval: _liveInterval,
      onTick: _onLiveTick,
      clock: ref.read(pollClockProvider),
    )).setLive(watchPageActivity(context, ref).isLive);

    // **The clock is stamped on an arrival, and only on an arrival.**
    //
    // `noteSuccess()` also used to be called from the body of `build`, off the
    // last *cached* value, which is precisely the case the band exists for.
    // When the metrics socket dies the provider keeps its final
    // `AsyncData(answered: true)`, so every incidental rebuild (a theme
    // change, the tick below, this listener's own `setState`) re-read that
    // stale value and pushed `lastSuccessAt` forward. `isStaleAt` was then
    // measured against a timestamp the same frame had just reset, so it could
    // never be true and the band could never appear. A rebuild is not news.
    ref.listen<AsyncValue<TrueNasDashboardMetrics>>(
      truenasDashboardMetricsProvider,
      (_, next) {
        if (next.asData?.value.answered == true) {
          _live?.noteSuccess();
        }
        if (mounted) setState(() {});
      },
    );

    final now = DateTime.now();
    final lastSuccessAt = _live?.lastSuccessAt;
    final staleAge = lastSuccessAt != null && _live!.isStaleAt(now)
        ? now.difference(lastSuccessAt)
        : null;

    final dashboard = ref.watch(truenasDashboardProvider);

    return TrueNasSectionScaffold(
      title: 'Dashboard',
      capabilityAreas: {TrueNasCapabilityArea.alerts.key},
      body: TrueNasConsoleShell(
        child: Column(
          children: [
            if (staleAge != null)
              FaultBand.stale(
                age: staleAge,
                detail: 'TrueNAS live metrics have not returned.',
                onRefresh: _refresh,
              ),
            Expanded(
              child: TrueNasAsyncBody(
                value: dashboard,
                onRetry: _refresh,
                skeleton: ListView(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  children: [AppSkeleton.listRows()],
                ),
                data: (data) => _DashboardBody(data: data),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final TrueNasDashboard data;
  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(truenasDashboardMetricsProvider);
    final system = data.system;
    final alerts = data.activeAlerts;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        // System summary.
        AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrueNasInfoRow(label: 'Hostname', value: system.hostname),
              TrueNasInfoRow(label: 'Version', value: system.version),
              TrueNasInfoRow(
                label: 'Uptime',
                value: system.uptimeSeconds != null
                    ? formatDuration(system.uptimeSeconds!)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // CPU + memory gauges, the same height whichever has more to say.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _CpuCard(system: system, metrics: metrics),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MemoryCard(system: system, metrics: metrics),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (metrics.value?.memoryBreakdown(totalBytes: system.physmemBytes)
            case final split?) ...[
          _MemoryBreakdownCard(split: split),
          const SizedBox(height: AppSpacing.md),
        ],

        const SectionHeader.flush(title: 'Network', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        _NetworkCard(
          metrics: metrics,
          interfaces: ref.watch(truenasDashboardInterfacesProvider),
        ),
        const SizedBox(height: AppSpacing.md),

        const SectionHeader.flush(title: 'Pool health', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        _PoolHealthCard(pools: data.pools),
        const SizedBox(height: AppSpacing.md),

        SectionHeader.flush(
          title: 'Alerts${alerts.isEmpty ? '' : ' (${alerts.length})'}',
          showChevron: false,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (alerts.isEmpty)
          AppCard.surfaceOutlined(
            child: Text(
              'No active alerts. 🎉',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _AlertCard(alert: alert),
            ),
      ],
    );
  }
}

class _CpuCard extends StatelessWidget {
  final TrueNasSystemInfo system;
  final AsyncValue<TrueNasDashboardMetrics> metrics;

  const _CpuCard({required this.system, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final usage = metrics.value?.cpuUsage;
    final cores = system.cores;
    final load = system.loadAvg1m;
    // Prefer measured CPU %, fall back to a load-per-core proxy.
    final fraction =
        usage ??
        (load != null ? (load / (cores ?? 1)).clamp(0, 1).toDouble() : null);
    final showsLoad = usage == null && load != null;

    return _GaugeCard(
      gauge: RadialGauge(
        value: fraction ?? 0,
        valueLabel: usage != null
            ? formatPercent(usage * 100)
            : (load != null ? load.toStringAsFixed(2) : '—'),
        caption: showsLoad ? 'load 1m' : 'used',
        color: ServiceKey.truenas.accent,
        size: 108,
      ),
      title: 'CPU',
      detail: cores != null ? countLabel(cores, 'core') : null,
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final TrueNasSystemInfo system;
  final AsyncValue<TrueNasDashboardMetrics> metrics;

  const _MemoryCard({required this.system, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final total = system.physmemBytes;
    final usage = metrics.value?.memoryUsage(totalBytes: total);

    return _GaugeCard(
      gauge: RadialGauge(
        value: usage ?? 0,
        valueLabel: usage != null ? formatPercent(usage * 100) : '—',
        caption: 'used',
        color: _memoryInUse(context),
        size: 108,
      ),
      title: 'Memory',
      detail: total != null ? '${formatSize(total)} total' : null,
    );
  }
}

/// The paint of memory in use: the gauge's arc and the services segment.
Color _memoryInUse(BuildContext context) =>
    statusToneColor(Theme.of(context).colorScheme, StatusTone.info);

/// A gauge over its name and one line about the whole: core count, total.
class _GaugeCard extends StatelessWidget {
  final Widget gauge;
  final String title;
  final String? detail;

  const _GaugeCard({required this.gauge, required this.title, this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard.surfaceOutlined(
      child: Column(
        children: [
          gauge,
          const SizedBox(height: AppSpacing.xs),
          Text(title, style: theme.textTheme.labelMedium),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.labelSmall!.tabular.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
        ],
      ),
    );
  }
}

/// Where the memory is: services, ZFS cache, free, as one bar and a legend.
class _MemoryBreakdownCard extends StatelessWidget {
  final TrueNasMemoryBreakdown split;

  const _MemoryBreakdownCard({required this.split});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inUse = _memoryInUse(context);
    final parts = [
      (label: 'Services', bytes: split.services, color: inUse, rim: false),
      (
        label: 'ZFS cache',
        bytes: split.zfsCache,
        color: inUse.withValues(alpha: 0.4),
        rim: false,
      ),
      (
        label: 'Free',
        bytes: split.free,
        color: theme.colorScheme.surfaceContainerHighest,
        // The track's colour, which a dot on the card would lose.
        rim: true,
      ),
    ];

    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          'Memory: ${formatBytes(split.services)} services, '
          '${formatBytes(split.zfsCache)} ZFS cache, '
          '${formatBytes(split.free)} free, of ${formatBytes(split.total)}',
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  // Stretched: an empty ColoredBox takes the smallest height
                  // it is allowed, which a loose cross axis makes zero.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final part in parts)
                      if (part.bytes > 0)
                        Expanded(
                          // Thousandths: a flex is an int, and a cache of a
                          // few hundred megabytes must still show.
                          flex: (part.bytes * 1000 / split.total).ceil(),
                          child: ColoredBox(color: part.color),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (final part in parts)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: part.color,
                                shape: BoxShape.circle,
                                border: part.rim
                                    ? Border.all(
                                        color: CupolaThemeColors.of(
                                          context,
                                        ).dimText,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              part.label,
                              style: theme.textTheme.labelSmall!.copyWith(
                                color: CupolaThemeColors.of(context).dimText,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          formatBytes(part.bytes),
                          style: theme.textTheme.labelMedium!
                              .weight(FontWeight.w600)
                              .tabular,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  final AsyncValue<TrueNasDashboardMetrics> metrics;
  final AsyncValue<List<TrueNasInterface>> interfaces;
  const _NetworkCard({required this.metrics, required this.interfaces});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return interfaces.when(
      skipLoadingOnReload: true,
      loading: () => AppSkeleton.listRows(count: 2),
      error: (_, _) => AppCard.surfaceOutlined(
        child: Text(
          'Network data unavailable',
          style: theme.textTheme.bodySmall,
        ),
      ),
      data: (list) {
        final upInterfaces = list.where((i) => i.addresses.isNotEmpty);
        // Already derived once per fetch by the provider.
        final series = metrics.value?.networkSeries ?? const <double>[];
        return AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (series.isNotEmpty) ...[
                Sparkline(values: series, color: ServiceKey.truenas.accent),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (upInterfaces.isEmpty)
                Text('No active interfaces', style: theme.textTheme.bodySmall)
              else
                for (final iface in upInterfaces)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          iface.isUp ? Icons.circle : Icons.circle_outlined,
                          size: 8,
                          // An interface that is down is backlog, not a fault:
                          // nothing failed, it is simply not carrying traffic.
                          color: statusToneColor(
                            theme.colorScheme,
                            iface.isUp
                                ? StatusTone.success
                                : StatusTone.neutral,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          iface.name,
                          style: theme.textTheme.bodyMedium!.weight(
                            FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            iface.addresses.join(', '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _PoolHealthCard extends StatelessWidget {
  final List<TrueNasPool> pools;
  const _PoolHealthCard({required this.pools});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (pools.isEmpty) {
      return AppCard.surfaceOutlined(
        child: Text('No pools reported.', style: theme.textTheme.bodySmall),
      );
    }
    return AppCard.surfaceOutlined(
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final pool in pools)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                // Amber for a degraded pool, not red: the NAS answered and told
                // us the pool is unhealthy. Red is for the host that says
                // nothing at all.
                color: statusToneColor(
                  theme.colorScheme,
                  pool.healthy ? StatusTone.success : StatusTone.warning,
                ).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    pool.healthy
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    size: 14,
                    color: statusToneColor(
                      theme.colorScheme,
                      pool.healthy ? StatusTone.success : StatusTone.warning,
                      surface: theme.colorScheme.surface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    pool.name,
                    style: theme.textTheme.labelMedium!.weight(FontWeight.w600),
                  ),
                  if (pool.usedFraction != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      formatPercent(pool.usedFraction! * 100),
                      style: theme.textTheme.labelSmall!.tabular.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  final TrueNasAlert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final level = alert.level.toUpperCase();
    // TrueNAS's own severities, mapped onto the app's four tones. CRITICAL and
    // ERROR are still faults the server is reporting, not a connection that
    // died: amber, like WARNING, because red would say the NAS is gone while
    // the alert it raised is on screen.
    final color = statusToneColor(colorScheme, switch (level) {
      'CRITICAL' || 'ERROR' || 'WARNING' => StatusTone.warning,
      _ => StatusTone.info,
    });

    return AppCard.surfaceOutlined(
      borderColor: color.withValues(alpha: 0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(alert.message, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: AppSpacing.sm),
          trueNasGatedButton(
            ref: ref,
            area: TrueNasCapabilityArea.alerts.key,
            verbPhrase: 'dismiss alerts',
            onTap: () => runTrueNasAction(
              context,
              ref,
              action: () =>
                  ref.read(truenasSystemApiProvider).dismissAlert(alert.id),
              successMessage: 'Alert dismissed',
              failureMessage: 'Could not dismiss alert',
              invalidate: [truenasDashboardProvider],
            ),
            builder: (context, onPressed, annotate) => TextButton(
              onPressed: onPressed,
              child: annotate(const Text('Dismiss')),
            ),
          ),
        ],
      ),
    );
  }
}
