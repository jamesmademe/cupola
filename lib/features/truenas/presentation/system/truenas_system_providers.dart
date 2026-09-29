import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/truenas/domain/models/credentials.dart';
import 'package:cupola/features/truenas/domain/models/system_info.dart';
import 'package:cupola/features/truenas/domain/models/network.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

/// `system.info`, on its own rather than through the dashboard snapshot.
///
/// The Power card needs exactly one field out of it — the hostname it asks to
/// be typed — and the dashboard provider it would otherwise have to watch drags
/// pools, alerts and services along with it on a 3-second poll.
final truenasSystemInfoProvider =
    FutureProvider.autoDispose<TrueNasSystemInfo?>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getSystemInfo();
    }, retry: noProviderRetry);

final truenasGeneralConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getGeneralConfig();
    }, retry: noProviderRetry);

final truenasAdvancedConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getAdvancedConfig();
    }, retry: noProviderRetry);

final truenasMailConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getMailConfig();
    }, retry: noProviderRetry);

final truenasUpdateStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).checkUpdateAvailable();
    }, retry: noProviderRetry);

final truenasNtpServersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getNtpServers();
    }, retry: noProviderRetry);

final truenasCertificatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getCertificates();
    }, retry: noProviderRetry);

final truenasAlertServicesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasSystemApiProvider).getAlertServices();
    }, retry: noProviderRetry);

final truenasNetworkConfigProvider =
    FutureProvider.autoDispose<TrueNasNetworkConfig>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasNetworkApiProvider).getConfig();
    }, retry: noProviderRetry);

final truenasInterfacesProvider =
    FutureProvider.autoDispose<List<TrueNasInterface>>((ref) async {
      ref.watch(truenasClientProvider);
      return ref.watch(truenasNetworkApiProvider).getInterfaces();
    }, retry: noProviderRetry);

final truenasUsersProvider = FutureProvider.autoDispose<List<TrueNasUser>>((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasCredentialsApiProvider).getUsers();
}, retry: noProviderRetry);

final truenasGroupsProvider = FutureProvider.autoDispose<List<TrueNasGroup>>((
  ref,
) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasCredentialsApiProvider).getGroups();
}, retry: noProviderRetry);
