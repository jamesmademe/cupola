/// What the requester can do with a request of hers: open its title, watch
/// it, take it back while it waits.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// Opens the title of [mine] on its page, where she can ask for more of it.
void openMyRequest(BuildContext context, MyRequest mine) {
  final media = mine.request.media;
  final id = media?.tmdbId;
  if (id == null) return;
  context.openSeerrTitle(
    mediaType: mine.request.type == 'tv' ? 'tv' : 'movie',
    id: id,
  );
}

/// Opens [at], Seerr's link to the title in the player it is set up with.
Future<void> watchMyRequest(BuildContext context, Uri at) async {
  // The row already filters, and this is the second half of the same rule: a
  // caller that ever hands this a server-controlled URI cannot turn it into
  // an `intent:` or `file:` launch.
  if (!UrlUtils.isLaunchableWebUri(at)) return;
  final opened = await launchUrl(at, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    SnackBarHelper.error(context, 'Could not open it');
  }
}

/// Takes back [mine], which still waits for approval: a neutral
/// confirmation, then `Request canceled`. Seerr refuses once the request was
/// answered, and says so; any other failure changed nothing, and reads so.
/// Her list is read again either way, since it is the list that is stale.
Future<void> cancelMyRequest(
  BuildContext context,
  WidgetRef ref,
  MyRequest mine,
) async {
  final result = await showAppConfirmDialog(
    context: context,
    title: '${Lexicon.cancelRequest}?',
    message: mine.title,
    icon: Icons.undo_rounded,
    confirmLabel: Lexicon.cancelRequest,
    cancelLabel: 'Keep it',
  );
  if (!result.confirmed || !context.mounted) return;
  try {
    await ref.read(seerrServiceProvider).deleteRequest(mine.request.id);
    if (context.mounted) {
      SnackBarHelper.success(context, Lexicon.requestCanceled);
    }
  } on SeerrRequestConflict {
    // Gone already, from another of her devices: what she wanted.
    if (context.mounted) {
      SnackBarHelper.success(context, Lexicon.requestCanceled);
    }
  } catch (error) {
    if (!context.mounted) return;
    if (seerrRefusalOf(error) == SeerrRefusal.noLongerCancellable) {
      SnackBarHelper.info(context, Lexicon.noLongerCancellable);
    } else {
      SnackBarHelper.error(
        context,
        'Could not cancel the request. ${Lexicon.nothingChanged}',
        cause: error,
      );
    }
  }
  invalidateSeerrRequests(ref.container);
}
