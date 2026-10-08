class RatingSource {
  final String name;
  final double value;
  final int votes;
  final String icon;

  const RatingSource({
    required this.name,
    required this.value,
    required this.votes,
    required this.icon,
  });
}

/// Fewer votes than this, and an average is a handful of opinions: a list
/// and the title's page leave it out, the episode graph draws it uncertain.
const int ratingVoteFloor = 20;

/// [average] as a score worth showing: null for a title nobody rated (TMDB
/// answers 0) and for an average over fewer than [ratingVoteFloor] votes,
/// which TMDB states as plainly as a million (a 10 from one vote). A count
/// of 0 or null is one the source did not send, and hides nothing.
double? ratingWorthShowing(double? average, {int? votes}) {
  if (average == null || average <= 0) return null;
  if (votes != null && votes > 0 && votes < ratingVoteFloor) return null;
  return average;
}
