import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_availability.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

export 'package:cupola/features/stream/domain/stream_availability.dart';

/// The external ids an arr can offer for one title, and what it knows about
/// that title to check a server's answer against.
///
/// A record so the family key gets structural equality for free. At least one
/// id must be non-null or the lookup is skipped — matching on a title would be
/// a guess, and this exists to state a fact. [kind], [title] and [year] never
/// start a lookup; they only narrow and verify what the ids found (see
/// `StreamExternalQuery`).
typedef StreamLookupKey = ({
  String? tmdbId,
  String? tvdbId,
  String? imdbId,
  StreamItemKind? kind,
  String? title,
  int? year,
});

/// Whether an arr's title is on a media server, and how far into it the viewer is.
///
/// **This is the answer to the duplicate-catalogue problem, and it is deliberately
/// a decoration rather than a second search source.** Adding Jellyfin and Plex as
/// their own global-search groups would make one film return in up to six
/// sections: Radarr and Sonarr "search" is a TMDB/TVDB *lookup*, not a library
/// search, so "Dune" already produces four. Instead the Stream fact rides on the
/// arr row that is already there — the same move `ArrMediaExtrasSection` makes for
/// Seerr data inside an arr screen.
///
/// The first server that has it wins. Two media servers indexing the same file is
/// a real setup, but "it is watchable, and you are 34 minutes in" is one fact, and
/// showing it twice would be noise rather than information.
///
/// **"Has it" means the server's answer survived [streamExternalMatchScore]**,
/// here as well as in the client. Each client already refuses an unverified row;
/// this gate is the contract restated at the one place every answer passes, so
/// a server client that forgets to check — or a new one — cannot put a wrong
/// "On Jellyfin" card on an arr page. A refused answer is "not verified", and
/// the next server is asked.
///
/// ## The four nothings, told apart
///
/// The answer is a [StreamAvailability], because "no card" was four facts: no
/// media server set up, a server that did not answer, a server that answered it
/// does not have the title, and a row that does not verify. The first server
/// that has it still wins. Otherwise, in the order the page must say them:
///
///  1. a server **failed** → that failure: a title missing from one server and
///     unknown on another is not "not on your server";
///  2. a row **did not verify** → not verified: nothing is claimed either way;
///  3. every server **answered empty** → not in the library, naming them;
///  4. no media server is set up → not set up, without asking anything.
final streamAvailabilityProvider = FutureProvider.autoDispose
    .family<StreamAvailability, StreamLookupKey>((ref, key) async {
      final settings = ref.watch(currentSettingsProvider);
      final servers = ServiceDomain.stream.services
          .where(settings.isServiceConfigured)
          .toList(growable: false);
      // Case a, decided before anything is asked.
      if (servers.isEmpty) return const StreamAvailability.notSetUp();

      if ((key.tmdbId ?? '').isEmpty &&
          (key.tvdbId ?? '').isEmpty &&
          (key.imdbId ?? '').isEmpty) {
        // Nothing to ask by: matching on a title would be a guess, and this
        // exists to state a fact. No claim either way.
        return const StreamAvailability.notVerified();
      }

      final query = StreamExternalQuery(
        tmdbId: key.tmdbId,
        tvdbId: key.tvdbId,
        imdbId: key.imdbId,
        kind: key.kind,
        title: key.title,
        year: key.year,
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);

      StreamAvailability? failed;
      var unverified = false;
      final answeredEmpty = <ServiceKey>[];
      for (final service in servers) {
        try {
          final client = service == ServiceKey.jellyfin
              ? ref.watch(jellyfinServerProvider)
              : ref.watch(plexServerProvider);
          final lookup = await client.lookupByExternalId(
            tmdbId: key.tmdbId,
            tvdbId: key.tvdbId,
            imdbId: key.imdbId,
            kind: key.kind,
            title: key.title,
            year: key.year,
            cancelToken: cancelToken,
          );
          final item = lookup.item;
          switch (lookup.outcome) {
            case StreamLookupOutcome.found:
              // The gate: a client's "found" is checked again here.
              if (item != null &&
                  streamExternalMatchScore(item, query) != null) {
                return StreamAvailability.found((service: service, item: item));
              }
              unverified = true;
            case StreamLookupOutcome.notVerified:
              unverified = true;
            case StreamLookupOutcome.notInLibrary:
              answeredEmpty.add(service);
          }
        } catch (error) {
          // A server that did not answer is not evidence the title is
          // missing. Kept, and the next server is still asked: it may have it.
          failed ??= StreamAvailability.failed(
            service,
            classifyConnectionFailure(error),
          );
        }
      }
      if (failed != null) return failed;
      if (unverified) return const StreamAvailability.notVerified();
      return StreamAvailability.notInLibrary(answeredEmpty);
    }, retry: noProviderRetry);

/// The verified match alone, for the surfaces that draw only a found title.
///
/// `noProviderRetry` like its source: the availability never throws for a
/// server that failed — it says so — so there is nothing here to retry.
final streamMatchProvider = FutureProvider.autoDispose
    .family<StreamMatch?, StreamLookupKey>((ref, key) async {
      return (await ref.watch(streamAvailabilityProvider(key).future)).match;
    }, retry: noProviderRetry);
