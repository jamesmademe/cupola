import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/qbittorrent/domain/models/rss.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';

final qbittorrentRssFeedsProvider = FutureProvider<List<QbittorrentRssFeed>>((
  ref,
) async {
  return ref.watch(qbittorrentServiceProvider).getRssFeeds();
}, retry: noProviderRetry);

final qbittorrentRssRulesProvider = FutureProvider<List<QbittorrentRssRule>>((
  ref,
) async {
  return ref.watch(qbittorrentServiceProvider).getRssRules();
}, retry: noProviderRetry);
