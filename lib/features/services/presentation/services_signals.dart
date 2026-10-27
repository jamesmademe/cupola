import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The two live figures one stack card shows.
///
/// Lives here rather than beside the KPI providers because it is a
/// Dashboard concern: the Portal's picker and the aggregate lines all want
/// exactly one figure and are right to. The card wants two, and reduces the same
/// KPI list through the same ranking (see `resolveServiceSignalPair`), so the
/// card's primary and the single figure can never disagree about which
/// metric matters.
///
/// Note the deliberate lack of error handling: an unreachable service leaves
/// this in `AsyncError`, and the cell renders its reachability instead. Swallowing
/// the error into a null pair here would make "no metric to report" and "this
/// service is down" the same value.
final serviceSignalPairProvider = FutureProvider.autoDispose
    .family<ServiceSignalPair?, ServiceKey>((ref, service) async {
      final kpis = await ref.watch(serviceKpiProvider(service).future);
      return resolveServiceSignalPair(kpis);
      // Derived from `serviceKpiProvider`, which carries the flag: without it
      // a failed read bounced between shimmer and dash on the default backoff.
    }, retry: noProviderRetry);

/// The two figures a **folded** card shows: the fleet's, not the lens's.
///
/// A card carrying `×2` beside one server's numbers is the lens wearing the
/// fleet's clothes: it reads as a total and is short by whatever the other
/// server holds. This reduces the aggregate through the same ranking
/// [serviceSignalPairProvider] uses, so a single-connection service cannot
/// disagree with itself depending on which provider the cell happened to watch.
///
/// Null where there is no aggregate to show: a dark connection, a connection
/// the app cannot yet read on its own, or figures that do not fold. See
/// [foldedServiceKpisProvider]. The card then draws `×N` and no figure, which
/// is what the design asks for and the only honest reading available.
final foldedServiceSignalPairProvider = FutureProvider.autoDispose
    .family<ServiceSignalPair?, ServiceKey>((ref, service) async {
      final kpis = await ref.watch(foldedServiceKpisProvider(service).future);
      return kpis == null ? null : resolveServiceSignalPair(kpis);
      // Derived from `serviceKpiProvider`, which carries the flag: without it
      // a failed read bounced between shimmer and dash on the default backoff.
    }, retry: noProviderRetry);
