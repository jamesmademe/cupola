import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

/// A title's Seerr record for the detail page.
///
/// `noProviderRetry`, like the person and collection lookups below: a failure
/// is asked once and reaches the page in its own words, under a Retry that
/// asks again. Riverpod's default re-ran the lookup ten times on a backoff,
/// behind a page that was already showing the failure.
final discoverDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({int id, String type})>((ref, arg) async {
      final service = ref.watch(seerrServiceProvider);
      if (arg.type == 'movie') {
        return service.getMovie(arg.id);
      } else {
        return service.getTv(arg.id);
      }
    }, retry: noProviderRetry);

/// Which numbering the lens's Seerr follows for its media codes
/// (`SeerrService.numbering`), so the detail page decodes them as the server
/// that sent them means them. Null until the server has said.
///
/// Kept on the connection's service, so a page opened twice asks once. It
/// never throws for a server that did not answer, and `noProviderRetry` for
/// the one throw left, a Seerr that is not set up, which no waiting changes.
final seerrNumberingProvider = FutureProvider.autoDispose<SeerrNumbering?>(
  (ref) => ref.watch(seerrServiceProvider).numbering(),
  retry: noProviderRetry,
);

/// Person (cast/crew) details for the Person page.
///
/// Fails when Seerr did not answer or answered with a failure, and resolves
/// to an empty person only when Seerr answered that it has none, so the page
/// can say "Seerr answered, but it has no record of them" and mean it.
/// `noProviderRetry`, so the failure reaches the page at once; Retry is there.
final personDetailProvider = FutureProvider.autoDispose
    .family<PersonDetail, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return PersonDetail.fromJson(await service.getPerson(id));
    }, retry: noProviderRetry);

/// A person's credits, in front of the camera and behind it, each with what
/// Seerr holds of the title. Fails like [personDetailProvider], so a dark
/// Seerr is not an empty filmography.
final personCreditsProvider = FutureProvider.autoDispose
    .family<PersonCombinedCredits, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return service.getPersonCredits(id);
    }, retry: noProviderRetry);

/// Full collection (with member movies) for the Collection page. Fails like
/// [personDetailProvider]; empty only when Seerr answered with nothing.
final collectionDetailProvider = FutureProvider.autoDispose
    .family<CollectionDetail, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return CollectionDetail.fromJson(await service.getCollection(id));
    }, retry: noProviderRetry);
