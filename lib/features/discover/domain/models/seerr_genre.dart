/// A TMDB genre as Seerr lists it, with the backdrops of a few of its titles
/// (`/discover/genreslider/{movie,tv}`), which the genre tiles are lit by.
class SeerrGenre {
  final int id;
  final String name;

  /// TMDB backdrop paths, first the most popular; empty when Seerr sent none.
  final List<String> backdrops;

  const SeerrGenre({
    required this.id,
    required this.name,
    this.backdrops = const [],
  });

  factory SeerrGenre.fromJson(Map<String, dynamic> json) {
    final backdrops = json['backdrops'];
    return SeerrGenre(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? '').toString(),
      backdrops: backdrops is List
          ? backdrops.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}
