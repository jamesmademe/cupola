import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';

final discoverDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({int id, String type})>((ref, arg) async {
      final service = ref.watch(seerrServiceProvider);
      if (arg.type == 'movie') {
        return service.getMovie(arg.id);
      } else {
        return service.getTv(arg.id);
      }
    });

/// Person (cast/crew) details for the Person page.
///
/// Fails when Seerr did not answer or answered with a failure, and resolves
/// to an empty person only when Seerr answered that it has none — so the page
/// can say "Seerr answered, but it has no record of them" and mean it.
/// `noProviderRetry`, so the failure reaches the page at once; Retry is there.
final personDetailProvider = FutureProvider.autoDispose
    .family<PersonDetail, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return PersonDetail.fromJson(await service.getPerson(id));
    }, retry: noProviderRetry);

/// A person's combined filmography for the Person page. Fails like
/// [personDetailProvider], so a dark Seerr is not an empty filmography.
final personCreditsProvider = FutureProvider.autoDispose
    .family<List<MediaPreview>, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return service.getPersonCombinedCredits(id);
    }, retry: noProviderRetry);

/// Full collection (with member movies) for the Collection page. Fails like
/// [personDetailProvider]; empty only when Seerr answered with nothing.
final collectionDetailProvider = FutureProvider.autoDispose
    .family<CollectionDetail, int>((ref, id) async {
      final service = ref.watch(seerrServiceProvider);
      return CollectionDetail.fromJson(await service.getCollection(id));
    }, retry: noProviderRetry);
