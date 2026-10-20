import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/domain/models/reporting.dart';
import 'package:cupola/features/truenas/presentation/dashboard/truenas_dashboard_screen.dart';

TrueNasReportingGraph _graph(
  String name,
  List<String> legend,
  List<List<double?>> data,
) => TrueNasReportingGraph(name: name, legend: legend, data: data);

void main() {
  group('TrueNasDashboardMetrics.cpuUsage', () {
    test('reads the aggregate of the 25.04+ per-core usage chart', () {
      // `truenas_cpu_usage.cpu`: `cpu` is the whole machine and every series
      // is already a busy percentage. No idle series exists, so the old
      // reading fell back to load average on every current TrueNAS.
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'cpu', 'cpu0', 'cpu1', 'cpu2', 'cpu3'],
          [
            [1770000000, 50, 50, 50, 50, 50],
            [1770000001, 12.5, 10, 20, 5, 15],
          ],
        ),
      );

      expect(metrics.cpuUsage, closeTo(0.125, 1e-9));
    });

    test('averages the cores when the aggregate is missing', () {
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'cpu0', 'cpu1'],
          [
            [1770000000, 10, 30],
          ],
        ),
      );

      expect(metrics.cpuUsage, closeTo(0.2, 1e-9));
    });

    test('is null when the chart carries no idle dimension', () {
      // netdata's `system.cpu` is a stacked percentage that *excludes* idle.
      // The old `(total - idle) / total` then reduced to total/total, so a
      // completely idle box read a confident 100%, and because that is not
      // null, the load-per-core fallback never got to run.
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'user', 'system', 'iowait'],
          [
            [1770000000, 1.5, 0.5, 0],
          ],
        ),
      );

      expect(metrics.cpuUsage, isNull);
    });

    test('is the busy share when an idle dimension is present', () {
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'user', 'system', 'idle'],
          [
            [1770000000, 20, 5, 75],
          ],
        ),
      );

      expect(metrics.cpuUsage, closeTo(0.25, 1e-9));
    });

    test('reads the newest sample, not the first', () {
      final metrics = TrueNasDashboardMetrics(
        cpu: _graph(
          'cpu',
          ['time', 'busy', 'idle'],
          [
            [1770000000, 10, 90],
            [1770000001, 40, 60],
          ],
        ),
      );

      expect(metrics.cpuUsage, closeTo(0.4, 1e-9));
    });

    test('is null with no graph and with no samples', () {
      expect(const TrueNasDashboardMetrics().cpuUsage, isNull);
      expect(
        TrueNasDashboardMetrics(
          cpu: _graph('cpu', ['time', 'idle'], const []),
        ).cpuUsage,
        isNull,
      );
    });
  });

  group('TrueNasDashboardMetrics.memoryUsage', () {
    const gib = 1024 * 1024 * 1024;

    test('is total minus the 25.04+ available series, over the total', () {
      // `truenas_meminfo.available` carries one series, in bytes.
      final metrics = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'available'],
          [
            [1770000000, 8.0 * gib],
            [1770000001, 24.0 * gib],
          ],
        ),
      );

      expect(metrics.memoryUsage(totalBytes: 32 * gib), closeTo(0.25, 1e-9));
    });

    test('leaves the ZFS ARC out, as the TrueNAS memory widget does', () {
      // `MemAvailable` excludes the ARC, which fills idle RAM: without this
      // a 32 GiB NAS running 4 GiB of services read about 90%.
      final metrics = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'available'],
          [
            [1770000000, 4.0 * gib],
          ],
        ),
        arc: _graph(
          'arcsize',
          ['time', 'size'],
          [
            [1770000000, 24.0 * gib],
          ],
        ),
      );

      expect(metrics.memoryUsage(totalBytes: 32 * gib), closeTo(0.125, 1e-9));
    });

    test('splits the total into services, ZFS cache and free', () {
      final split = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'available'],
          [
            [1770000000, 4.0 * gib],
          ],
        ),
        arc: _graph(
          'arcsize',
          ['time', 'size'],
          [
            [1770000000, 24.0 * gib],
          ],
        ),
      ).memoryBreakdown(totalBytes: 32 * gib)!;

      expect(split.free, 4 * gib);
      expect(split.zfsCache, 24 * gib);
      expect(split.services, 4 * gib);
      expect(split.services + split.zfsCache + split.free, split.total);
    });

    test('has no split without the ARC series', () {
      final metrics = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'available'],
          [
            [1770000000, 8.0 * gib],
          ],
        ),
      );

      expect(metrics.memoryBreakdown(totalBytes: 32 * gib), isNull);
      expect(metrics.memoryUsage(totalBytes: 32 * gib), closeTo(0.75, 1e-9));
    });

    test('is null with no total, and for a zero that is a gap', () {
      TrueNasDashboardMetrics available(double bytes) =>
          TrueNasDashboardMetrics(
            memory: _graph(
              'memory',
              ['time', 'available'],
              [
                [1770000000, bytes],
              ],
            ),
          );

      expect(available(8.0 * gib).memoryUsage(), isNull);
      expect(available(0).memoryUsage(totalBytes: 32 * gib), isNull);
    });

    test('is null when no dimension is labelled used', () {
      // Mirror of the CPU bug: the old arithmetic answered a confident 0%.
      final metrics = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'free', 'cached', 'buffers'],
          [
            [1770000000, 4, 2, 1],
          ],
        ),
      );

      expect(metrics.memoryUsage(totalBytes: 8), isNull);
    });

    test('is the used share when the dimension exists', () {
      final metrics = TrueNasDashboardMetrics(
        memory: _graph(
          'memory',
          ['time', 'used', 'free'],
          [
            [1770000000, 3, 1],
          ],
        ),
      );

      expect(metrics.memoryUsage(totalBytes: 8), closeTo(0.75, 1e-9));
    });
  });
}
