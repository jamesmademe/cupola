import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/domain/models/share.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

final truenasSmbSharesProvider =
    FutureProvider.autoDispose<List<TrueNasSmbShare>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSharingApiProvider).getSmbShares();
    }, retry: noProviderRetry);

final truenasNfsSharesProvider =
    FutureProvider.autoDispose<List<TrueNasNfsShare>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSharingApiProvider).getNfsShares();
    }, retry: noProviderRetry);

final truenasIscsiTargetsProvider =
    FutureProvider.autoDispose<List<TrueNasIscsiTarget>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSharingApiProvider).getIscsiTargets();
    }, retry: noProviderRetry);

/// All system services (used for share service-state banners and the System
/// › Services screen).
final truenasServicesProvider =
    FutureProvider.autoDispose<List<TrueNasServiceItem>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getServices();
    }, retry: noProviderRetry);
