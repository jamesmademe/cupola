import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/media/presentation/arr_public_poster.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';

/// The title a live session plays, on the connection playing it: the server's
/// own id for it (`StreamSession.titleId`). Empty [instanceId] is the lens.
typedef StreamSessionTitle = ({
  ServiceKey service,
  String instanceId,
  String titleId,
});

/// [session]'s title on [service]'s connection [instanceId], or null for a
/// session whose server named no movie or series.
StreamSessionTitle? streamSessionTitleOf(
  ServiceKey service,
  String instanceId,
  StreamSession session,
) {
  final titleId = session.titleId;
  if (titleId == null || titleId.isEmpty) return null;
  return (service: service, instanceId: instanceId, titleId: titleId);
}

/// The public poster of what a session plays: the ids the server holds for
/// its title (`StreamServerClient.getTitleKey`), then the arrs' record of them
/// ([arrPublicPosterProvider]). A media server's own artwork is behind its
/// key, so this is how a room or a card about a session reads a light. Null
/// when the server holds no id, or no arr holds the title.
final streamSessionPosterProvider = FutureProvider.autoDispose
    .family<String?, StreamSessionTitle>((ref, title) async {
      final client = ref.watch(
        streamClientForProvider((
          service: title.service,
          instanceId: title.instanceId,
        )),
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      final key = await client.getTitleKey(
        title.titleId,
        cancelToken: cancelToken,
      );
      if (key == null || !ref.mounted) return null;
      return ref.watch(arrPublicPosterProvider(key).future);
    }, retry: noProviderRetry);
