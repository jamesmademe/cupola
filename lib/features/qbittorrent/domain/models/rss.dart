import 'package:flutter/foundation.dart';

import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';

/// One leaf in qBittorrent's nested `GET /api/v2/rss/items` tree.
@immutable
class QbittorrentRssFeed {
  const QbittorrentRssFeed({
    required this.path,
    required this.url,
    required this.title,
    required this.unreadCount,
    required this.isLoading,
    required this.hasError,
  });

  final String path;
  final String url;
  final String title;

  /// Unread articles, or **null when this WebUI did not send the articles to
  /// count**.
  ///
  /// An older build answers `/rss/items` with a bare URL string per feed even
  /// under `withData=true`; there is no article collection in that shape, so
  /// there is no count. Reporting it as `0` said "nothing new here" about a
  /// question the server was never asked.
  final int? unreadCount;
  final bool isLoading;
  final bool hasError;

  String get displayName =>
      title.trim().isEmpty ? path.split(r'\').last : title;
}

/// One qBittorrent RSS auto-download rule.
@immutable
class QbittorrentRssRule {
  const QbittorrentRssRule({
    required this.name,
    required this.enabled,
    required this.mustContain,
    required this.mustNotContain,
    required this.affectedFeeds,
    required this.assignedCategory,
    required this.lastMatch,
  });

  final String name;
  final bool enabled;
  final String mustContain;
  final String mustNotContain;
  final List<String> affectedFeeds;
  final String assignedCategory;
  final String lastMatch;

  factory QbittorrentRssRule.fromJson(String name, Map<String, dynamic> json) {
    final rawFeeds = json['affectedFeeds'];
    return QbittorrentRssRule(
      name: name,
      enabled: parseBool(json['enabled']),
      mustContain: json['mustContain']?.toString() ?? '',
      mustNotContain: json['mustNotContain']?.toString() ?? '',
      affectedFeeds: rawFeeds is List
          ? rawFeeds.map((value) => value.toString()).toList(growable: false)
          : const [],
      assignedCategory: json['assignedCategory']?.toString() ?? '',
      lastMatch: json['lastMatch']?.toString() ?? '',
    );
  }
}

/// Flattens qBittorrent's folder tree while preserving each full item path.
///
/// Older WebUI API versions return a feed leaf as a URL string. Newer builds
/// return an object when `withData=true`, carrying `url`, `title`, loading/error
/// state and an article collection. Both are protocol shapes, so both are
/// accepted without treating every map as a feed.
List<QbittorrentRssFeed> qbittorrentRssFeedsFromJson(Object? raw) {
  if (raw is! Map) return const [];
  final feeds = <QbittorrentRssFeed>[];

  void visit(Map<dynamic, dynamic> node, String parent) {
    for (final entry in node.entries) {
      final name = entry.key.toString();
      final path = parent.isEmpty ? name : '$parent\\$name';
      final value = entry.value;
      if (value is String) {
        // The legacy shape: the leaf is the feed URL and nothing else. No
        // articles came with it, so no count can be stated — see
        // [QbittorrentRssFeed.unreadCount].
        feeds.add(
          QbittorrentRssFeed(
            path: path,
            url: value,
            title: name,
            unreadCount: null,
            isLoading: false,
            hasError: false,
          ),
        );
        continue;
      }
      if (value is! Map) continue;
      final map = value.cast<dynamic, dynamic>();
      final url = map['url']?.toString() ?? '';
      if (url.isEmpty) {
        visit(map, path);
        continue;
      }

      final articles = map['articles'];
      final articleValues = articles is Map
          ? articles.values
          : articles is List
          ? articles
          : const <dynamic>[];
      final unread = articleValues.where((article) {
        if (article is! Map) return false;
        return !parseBool(article['isRead']);
      }).length;
      feeds.add(
        QbittorrentRssFeed(
          path: path,
          url: url,
          title: map['title']?.toString() ?? name,
          unreadCount: unread,
          isLoading: parseBool(map['isLoading']),
          hasError: parseBool(map['hasError']),
        ),
      );
    }
  }

  visit(raw, '');
  return List.unmodifiable(feeds);
}

List<QbittorrentRssRule> qbittorrentRssRulesFromJson(Object? raw) {
  if (raw is! Map) return const [];
  return List.unmodifiable([
    for (final entry in raw.entries)
      if (entry.value is Map)
        QbittorrentRssRule.fromJson(
          entry.key.toString(),
          (entry.value as Map).cast<String, dynamic>(),
        ),
  ]);
}
