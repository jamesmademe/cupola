import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';

/// One record on one named connection: the connection is part of the key,
/// so an author opened from a second Readarr reads that Readarr.
typedef ReadarrRecordRef = ({String instanceId, int id});

/// The author an author's page shows. A failure reaches the page, which says
/// why; Retry and a pull read it again, nothing retries on its own.
final readarrAuthorProvider = FutureProvider.autoDispose
    .family<ReadarrAuthor, ReadarrRecordRef>(
      (ref, item) => _readarr(ref, item.instanceId).getAuthorOrThrow(item.id),
      retry: noProviderRetry,
    );

/// The author's books, every one Readarr knows of.
final readarrAuthorBooksProvider = FutureProvider.autoDispose
    .family<List<ReadarrBook>, ReadarrRecordRef>(
      (ref, item) => _readarr(ref, item.instanceId).getBooks(item.id),
      retry: noProviderRetry,
    );

ReadarrService _readarr(Ref ref, String instanceId) => instanceId.isEmpty
    ? ref.watch(readarrServiceProvider)
    : ref.watch(readarrServiceForProvider(instanceId));
