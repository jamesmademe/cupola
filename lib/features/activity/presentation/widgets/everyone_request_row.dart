import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/everyones_requests.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/requests/presentation/my_request_actions.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One of the household's requests: the title, where it stands and when in
/// its tone, and who asked where the gate lets it say; under them the Seerr
/// it is on, once the list holds two. Opens the title; [actions] on a long press or a secondary
/// click.
class EveryoneRequestRow extends StatelessWidget {
  const EveryoneRequestRow({
    super.key,
    required this.mine,
    required this.now,
    required this.divided,
    this.connection,
    this.namesWho = true,
    this.actions = const [],
  });

  final MyRequest mine;
  final DateTime now;
  final bool divided;

  /// `Seerr Friends`, when the list holds more than one Seerr.
  final String? connection;

  /// Whether the row names who asked: where the connection sees everyone's
  /// requests, never to the requester.
  final bool namesWho;

  final List<RowAction> actions;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      scheme,
      everyonesTone(mine.stage),
      surface: room.slab,
    );
    final line = everyonesLine(mine, now);
    final who = namesWho ? mine.request.requestedBy?.displayName : null;
    // The poster: the row's art is portrait, and the wide artwork Ready to
    // watch draws would show a slice of its middle.
    final poster = ImageUtils.buildTmdbPosterUrl(
      mine.request.media?.posterPath,
    );
    return ActivityRowFrame(
      divided: divided,
      label: mine.title,
      // Spoken without the middle dot, which a screen reader names.
      value: [spokenFromDotted(line), ?who, ?connection].join(', '),
      onTap: () => openMyRequest(context, mine),
      actions: actions,
      art: HomeRowArt(
        posterUrl: poster.isEmpty ? null : poster,
        icon: ServiceKey.seerr.icon,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                mine.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.row.copyWith(color: room.ink),
              ),
            ),
            if (who != null && who.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(who, style: AppType.meta.copyWith(color: room.inkSecondary)),
            ],
          ],
        ),
        Text(
          line,
          style: AppType.meta.weight(FontWeight.w600).copyWith(color: tone),
        ),
        if (connection case final connection?)
          Text(
            connection,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
      ],
    );
  }
}
