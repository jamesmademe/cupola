import 'package:cupola/features/truenas/domain/models/alert.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/domain/models/system_info.dart';

/// Aggregated dashboard snapshot (system, pools, alerts, services).
class TrueNasDashboard {
  final TrueNasSystemInfo system;
  final List<TrueNasPool> pools;
  final List<TrueNasAlert> alerts;
  final List<TrueNasServiceItem> services;

  const TrueNasDashboard({
    required this.system,
    required this.pools,
    required this.alerts,
    required this.services,
  });

  /// Active (non-dismissed) alerts.
  List<TrueNasAlert> get activeAlerts =>
      alerts.where((a) => !a.dismissed).toList(growable: false);
}
