/// An arr's quality name in the page's words: the resolution first, then
/// where the release came from. `Bluray-1080p` reads `1080p Bluray`,
/// `WEBDL-720p` reads `720p WEB`, `Remux-2160p` reads `2160p Remux`.
///
/// A name that is not `Source-Resolution` (`DVD`, `SDTV`, a custom profile's
/// own) is kept as the arr wrote it.
String qualityWords(String qualityName) {
  final match = RegExp(
    r'^([A-Za-z]+(?:-[A-Za-z]+)?)-(\d{3,4}p)$',
  ).firstMatch(qualityName.trim());
  if (match == null) return qualityName.trim();
  final source = switch (match.group(1)!.toLowerCase()) {
    'bluray' => 'Bluray',
    'remux' || 'bluray-remux' => 'Remux',
    'webdl' || 'web' => 'WEB',
    'webrip' => 'WEBRip',
    'hdtv' => 'HDTV',
    'raw-hd' => 'Raw HD',
    final other => other.toUpperCase(),
  };
  return '${match.group(2)} $source';
}

/// Whether [qualityName] is a 2160p one: the copy the page marks `4K`.
bool isUhdQuality(String? qualityName) =>
    (qualityName ?? '').toLowerCase().contains('2160p');
