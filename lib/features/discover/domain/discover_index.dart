/// The atrium's indexes, each a door of the lobby or a link under it, and
/// each a page of its own (`ServiceRoutes.discoverIndex`).
enum DiscoverIndex {
  trending('Trending'),
  genres('Genres'),
  networks('Networks'),
  studios('Studios'),
  people('People'),
  decades('Decades'),
  moods('Moods'),
  languages('Languages');

  const DiscoverIndex(this.label);
  final String label;
}
