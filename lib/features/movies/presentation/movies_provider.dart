import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Radarr library wall, with a failed fetch allowed to reach the wall.
///
/// It read `getMovies`, which swallows every failure into `[]`, so a Radarr
/// that was down resolved this *successfully* and the wall said "No items
/// found" — a library that exists and is empty, the opposite of what happened.
/// The wall is the whole library in one request: there is no partial answer
/// to show beside a failed one, so the failure is what it has to show.
///
/// `retry: noProviderRetry` because the KPI peek above the wall reads the same
/// library with that policy: under the default one the rail said "—" at once
/// while the wall sat on a spinner for the better part of a minute. Retry and
/// pull-to-refresh are the user's call. See `lib/core/providers/provider_retry.dart`.
final moviesProvider = FutureProvider<List<RadarrMovie>>((ref) async {
  final service = ref.watch(radarrServiceProvider);
  return service.getMoviesOrThrow();
}, retry: noProviderRetry);
