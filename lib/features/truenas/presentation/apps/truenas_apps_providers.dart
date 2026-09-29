import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/truenas/domain/models/app.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

final truenasAppsProvider = FutureProvider.autoDispose<List<TrueNasApp>>((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasAppsApiProvider).getApps();
}, retry: noProviderRetry);

final truenasAppProvider = FutureProvider.autoDispose
    .family<TrueNasApp?, String>((ref, name) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasAppsApiProvider).getApp(name);
    }, retry: noProviderRetry);
