import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/media_value_sheet.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/presentation/request_form_provider.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Where a person chose to send a request they approve.
typedef ApproveChoice = ({
  SeerrArrServer server,
  int? profileId,
  String? rootFolder,
});

/// Whether [choice] sends the request anywhere [target], what the sheet
/// opened on, did not: then it is edited before it is approved.
///
/// Against the target, never the request's own fields: a request that names
/// no profile goes with its server's, and choosing that one again is no
/// change. Comparing with the request sent an edit on every approval.
bool approveChoiceChanges(SeerrApproveTarget target, ApproveChoice choice) =>
    choice.server.id != target.server?.id ||
    choice.profileId != target.profileId ||
    choice.rootFolder != target.rootFolder;

/// The quality profiles and root folders Seerr offers on one server
/// (`GET /api/v1/service/radarr|sonarr/{id}`).
final seerrServerChoicesProvider = FutureProvider.autoDispose
    .family<
      ({List<QualityProfileOption> profiles, List<RootFolderOption> folders}),
      ({String instanceId, ServiceKey arr, int serverId})
    >((ref, source) async {
      final service = ref.watch(seerrServiceForProvider(source.instanceId));
      final data = source.arr == ServiceKey.sonarr
          ? await service.getSonarrProfiles(source.serverId)
          : await service.getRadarrProfiles(source.serverId);
      return (
        profiles: [
          for (final json
              in (data['profiles'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>())
            QualityProfileOption.fromJson(json),
        ],
        folders: [
          for (final json
              in (data['rootFolders'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>())
            RootFolderOption.fromJson(json),
        ],
      );
    }, retry: noProviderRetry);

/// The servers [request] may go to: Seerr's of its kind and its copy, since
/// Seerr does not move a request between its standard and its 4K copy.
List<SeerrArrServer> seerrApproveServers(
  SeerrRequest request,
  List<SeerrArrServer> servers,
) => [
  for (final server in servers)
    if (server.is4k == request.is4k) server,
];

/// Asks where an approved request goes, and answers the choice, or null when
/// the person closed the sheet.
///
/// The sheet opens on where Seerr would send it ([target]); a person may
/// pick another server of the same copy, another quality profile and
/// another root folder. A series request that carries no seasons cannot be
/// changed (Seerr's edit needs them), and then the sheet only shows.
Future<ApproveChoice?> showApproveRequestSheet(
  BuildContext context, {
  required String instanceId,
  required String title,
  required SeerrRequest request,
  required SeerrApproveTarget target,
  required List<SeerrArrServer> servers,
  required Iterable<ServiceInstance> connections,
  required String Function(ServiceInstance connection) connectionTitle,
}) {
  final requester = request.requestedBy?.displayName.trim();
  return AppBottomSheet.show<ApproveChoice>(
    context: context,
    title: 'Approve $title',
    subtitle: [
      if (requester != null && requester.isNotEmpty) '$requester asked',
      request.is4k ? '4K' : 'Standard',
    ].join(dotSeparator),
    showClose: true,
    builder: (context) => ApproveRequestBody(
      instanceId: instanceId,
      title: title,
      request: request,
      target: target,
      servers: seerrApproveServers(request, servers),
      connections: connections,
      connectionTitle: connectionTitle,
    ),
  );
}

/// The approve sheet's body; see [showApproveRequestSheet].
class ApproveRequestBody extends ConsumerStatefulWidget {
  const ApproveRequestBody({
    super.key,
    required this.instanceId,
    required this.title,
    required this.request,
    required this.target,
    required this.servers,
    required this.connections,
    required this.connectionTitle,
  });

  final String instanceId;
  final String title;
  final SeerrRequest request;
  final SeerrApproveTarget target;

  /// The servers of the request's copy, the one [target] names among them.
  final List<SeerrArrServer> servers;
  final Iterable<ServiceInstance> connections;
  final String Function(ServiceInstance connection) connectionTitle;

  @override
  ConsumerState<ApproveRequestBody> createState() => _ApproveRequestBodyState();
}

class _ApproveRequestBodyState extends ConsumerState<ApproveRequestBody> {
  late SeerrArrServer _server = widget.target.server!;
  late int? _profileId = widget.target.profileId;
  late String? _rootFolder = widget.target.rootFolder;

  /// Seerr's edit of a series needs its seasons: one that carries none goes
  /// as it is.
  bool get _changeable =>
      widget.request.type != 'tv' ||
      (widget.request.seasons?.isNotEmpty ?? false);

  void _pickServer(SeerrArrServer server) {
    if (server.id == _server.id) return;
    // A server has its own profiles and folders: the ones it sends with
    // when nobody chooses.
    setState(() {
      _server = server;
      _profileId = server.activeProfileId;
      _rootFolder = server.activeDirectory;
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final choices = ref.watch(
      seerrServerChoicesProvider((
        instanceId: widget.instanceId,
        arr: widget.target.arr,
        serverId: _server.id,
      )),
    );
    final listed = choices.value;
    final profile = listed?.profiles
        .where((profile) => profile.id == _profileId)
        .firstOrNull;
    final folder = listed?.folders
        .where((folder) => folder.path == _rootFolder)
        .firstOrNull;
    final sentTo = widget.target.sentTo(
      _server,
      connections: widget.connections,
      profileId: _profileId,
      rootFolder: _rootFolder,
    );
    final quiet = AppType.meta
        .weight(FontWeight.w400)
        .copyWith(color: room.inkSecondary);
    final picksServer = _changeable && widget.servers.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (picksServer) ...[
          Text(
            'Server',
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectionPills<SeerrArrServer>.wrap(
            values: widget.servers,
            selected: widget.servers
                .where((server) => server.id == _server.id)
                .first,
            labelBuilder: _serverName,
            onSelected: _pickServer,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        MediaGroup(
          children: [
            if (!picksServer)
              MediaValueRow(
                label: 'Server',
                value: Text(
                  _serverName(_server),
                  textAlign: TextAlign.end,
                  style: quiet,
                ),
              ),
            MediaValueRow(
              label: 'Quality profile',
              value: Text(
                profile?.name ?? _server.activeProfileName ?? '',
                textAlign: TextAlign.end,
                style: quiet,
              ),
              onTap: _changeable && (listed?.profiles.length ?? 0) > 1
                  ? () => _pickProfile(listed!.profiles, profile)
                  : null,
            ),
            if (_rootFolder case final path?)
              MediaValueRow(
                label: 'Root folder',
                value: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      path,
                      textAlign: TextAlign.end,
                      style: AppType.mono.copyWith(color: room.inkSecondary),
                    ),
                    if (folder?.freeSpace case final free?)
                      Text(
                        '${formatBytes(free)} free',
                        style: AppType.caption.copyWith(
                          color: room.inkTertiary,
                        ),
                      ),
                  ],
                ),
                onTap: _changeable && (listed?.folders.length ?? 0) > 1
                    ? () => _pickFolder(listed!.folders)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final line in [
          sentTo.confirmation(
            widget.title,
            connectionTitle: widget.connectionTitle,
          ),
          if (choices.hasError)
            'Seerr did not list the profiles and folders, so it goes with '
                'these.',
          if (!_changeable)
            'Seerr changes a series request only with its seasons, and this '
                'one carries none, so it goes as it is.',
        ])
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Text(line, style: quiet),
          ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          // The sheet's one primary, the verb the confirmation always had.
          style: AppTheme.primaryButtonStyle(context),
          onPressed: () => Navigator.of(context).pop<ApproveChoice>((
            server: _server,
            profileId: _profileId,
            rootFolder: _rootFolder,
          )),
          child: const Text('Approve request'),
        ),
      ],
    );
  }

  /// A server by Seerr's name for it, or its kind when it has none.
  String _serverName(SeerrArrServer server) {
    if (server.connectionIn(widget.connections) case final connection?) {
      return widget.connectionTitle(connection);
    }
    if (server.name.isNotEmpty) return server.name;
    return server.is4k ? '4K ${server.service.title}' : server.service.title;
  }

  Future<void> _pickProfile(
    List<QualityProfileOption> profiles,
    QualityProfileOption? current,
  ) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: _profileId,
      currentLabel: current?.name ?? '',
      options: [
        for (final profile in profiles)
          MediaDetailValueOption(value: profile.id, label: profile.name),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _profileId = picked.value);
    }
  }

  Future<void> _pickFolder(List<RootFolderOption> folders) async {
    final picked = await showMediaValueSheet<String>(
      context,
      title: 'Root folder',
      value: _rootFolder,
      currentLabel: _rootFolder ?? '',
      options: [
        for (final folder in folders)
          MediaDetailValueOption(value: folder.path, label: folder.path),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _rootFolder = picked.value);
    }
  }
}
