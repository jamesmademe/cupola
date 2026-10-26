import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/utils/url_utils.dart';

typedef ImageSource = ({String url, Map<String, String>? headers});

/// Utility class for extracting and building image URLs from *arr service
/// responses.
class ImageUtils {
  /// Extracts a poster URL from an images list returned by Radarr/Sonarr/Lidarr.
  ///
  /// The method searches for images with specified cover types and builds
  /// image sources with authentication headers when needed.
  ///
  /// Parameters:
  /// - [images]: List of image objects from the API response
  /// - [baseUrl]: Base URL of the *arr service (for local images)
  /// - [apiKey]: API key for authentication (for local images)
  /// - [coverTypes]: List of cover type strings to search for (default: ['poster', 'cover'])
  ///
  /// Returns the image URL and optional headers, or an empty image source if
  /// nothing suitable is found.
  static ImageSource extractPosterUrl(
    List<dynamic>? images, {
    required String baseUrl,
    required String apiKey,
    List<String> coverTypes = const ['poster', 'cover'],
  }) {
    if (images == null || images.isEmpty) {
      return (url: '', headers: null);
    }

    // Find the first matching cover type
    dynamic coverImage;
    for (final type in coverTypes) {
      final matches = images.where((img) => img['coverType'] == type);
      if (matches.isNotEmpty) {
        coverImage = matches.first;
        break;
      }
    }

    if (coverImage == null) return (url: '', headers: null);

    final remoteUrl = coverImage['remoteUrl'] as String?;
    final localUrl = coverImage['url'] as String?;

    // Prefer remote URL if it's a full HTTP URL
    if (remoteUrl != null && remoteUrl.startsWith('http')) {
      return (
        url: sizedRemote(remoteUrl, coverImage['coverType']?.toString()),
        headers: null,
      );
    }

    // Fall back to building a local URL authenticated via headers: the key,
    // and whatever the connection presents to a gateway in front of it, since
    // the artwork crosses that gateway like every other request. Only for the
    // connection's own address; a remote URL above goes out with neither.
    final path = remoteUrl ?? localUrl;
    if (path != null && baseUrl.isNotEmpty && apiKey.isNotEmpty) {
      return (
        url: UrlUtils.buildUrl(baseUrl, path),
        headers: {
          ...ConnectionAccessRegistry.headersFor(baseUrl),
          'X-Api-Key': apiKey,
        },
      );
    }

    return (url: '', headers: null);
  }

  /// [url] at the size the app draws a [coverType] at, where its host
  /// serves one: an arr hands TMDB's artwork over at `original`, a poster of
  /// a few megabytes for a tile a few hundred pixels wide, and TMDB serves
  /// the same picture smaller under the same path. A poster is drawn at most
  /// as the hero of a title's page, about 600 pixels wide on a dense phone,
  /// and `w780` covers it; a fanart spans a phone or a window's well, and
  /// `w1280` covers that. Every other host, and every other kind, is left as
  /// it came.
  static String sizedRemote(String url, String? coverType) {
    final size = switch (coverType) {
      'poster' => 'w780',
      'fanart' => 'w1280',
      _ => null,
    };
    if (size == null) return url;
    const original = 'https://image.tmdb.org/t/p/original/';
    return url.startsWith(original)
        ? 'https://image.tmdb.org/t/p/$size/${url.substring(original.length)}'
        : url;
  }

  /// Builds a TMDB poster URL from a poster path.
  ///
  /// Parameters:
  /// - [posterPath]: The poster path from TMDB (e.g., "/abc123.jpg")
  /// - [size]: Image size (default: 'w500', options: 'w92', 'w154', 'w185', 'w342', 'w500', 'w780', 'original')
  static String buildTmdbPosterUrl(String? posterPath, {String size = 'w500'}) {
    if (posterPath == null || posterPath.isEmpty) return '';
    return 'https://image.tmdb.org/t/p/$size$posterPath';
  }

}
