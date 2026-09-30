import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Lidarr library wall, with a failed fetch allowed to reach the wall.
///
/// See `moviesProvider`: off the swallowing `getArtists` a dark Lidarr read
/// "No items found".
final musicProvider = FutureProvider<List<LidarrArtist>>((ref) async {
  final service = ref.watch(lidarrServiceProvider);
  return service.getArtistsOrThrow();
}, retry: noProviderRetry);
