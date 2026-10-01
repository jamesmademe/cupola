class LidarrAlbum {
  final int id;

  /// MusicBrainz's release group id: the album's identity across every
  /// Lidarr, where [id] is only this server's. Empty when Lidarr sent none.
  final String foreignAlbumId;

  final String title;
  final String? releaseDate;
  final bool monitored;
  final List<dynamic> images;
  final Map<String, dynamic>? statistics;

  const LidarrAlbum({
    required this.id,
    this.foreignAlbumId = '',
    required this.title,
    this.releaseDate,
    required this.monitored,
    required this.images,
    this.statistics,
  });

  String get year {
    if (releaseDate != null && releaseDate!.length >= 4) {
      return releaseDate!.substring(0, 4);
    }

    return '';
  }

  int get trackCount => (statistics?['totalTrackCount'] as num?)?.toInt() ?? 0;

  int get trackFileCount =>
      (statistics?['trackFileCount'] as num?)?.toInt() ?? 0;

  double get completionPercent =>
      trackCount > 0 ? trackFileCount / trackCount : 0.0;

  factory LidarrAlbum.fromJson(Map<String, dynamic> json) {
    final rawStatistics = json['statistics'];

    return LidarrAlbum(
      id: (json['id'] as num?)?.toInt() ?? 0,
      foreignAlbumId: (json['foreignAlbumId'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Unknown album',
      releaseDate: json['releaseDate'] as String?,
      monitored: json['monitored'] as bool? ?? false,
      images: json['images'] as List<dynamic>? ?? const [],
      statistics: rawStatistics is Map<String, dynamic> ? rawStatistics : null,
    );
  }
}
