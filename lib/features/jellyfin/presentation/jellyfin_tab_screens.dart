import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

/// Read-only household users from Jellyfin's `/Users` endpoint.
///
/// The design also specifies enable, library-access and delete controls. Those
/// are deliberately absent here: [JellyfinClient] exposes none of those writes,
/// and a control that can only fail is a promise Cupola cannot keep.
///
/// `/Users` is elevated like `/Devices` and `/ScheduledTasks`, so a household
/// member's token gets the same calm placeholder as those two tabs rather than
/// a refusal drawn as a fault.
class JellyfinUsersScreen extends ConsumerWidget {
  const JellyfinUsersScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    if (ref.watch(jellyfinLacksAdministratorProvider)) {
      return _needsAdministrator(context, ref, 'users', topPadding);
    }
    return ServiceListPage<JellyfinUserDto>(
      service: ServiceKey.jellyfin,
      topPadding: topPadding,
      value: ref.watch(jellyfinUsersProvider),
      serviceName: 'Jellyfin users',
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No users',
      emptyMessage: 'Jellyfin returned no household users.',
      onRetry: () => ref.invalidate(jellyfinUsersProvider),
      summary: _usersSummary,
      rowBuilder: (user) => _UserRow(user: user),
    );
  }
}

/// Read-only device inventory from Jellyfin's `/Devices` endpoint.
class JellyfinDevicesScreen extends ConsumerWidget {
  const JellyfinDevicesScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    if (ref.watch(jellyfinLacksAdministratorProvider)) {
      return _needsAdministrator(context, ref, 'devices', topPadding);
    }
    return ServiceListPage<JellyfinDevice>(
      service: ServiceKey.jellyfin,
      topPadding: topPadding,
      value: ref.watch(jellyfinDevicesProvider),
      serviceName: 'Jellyfin devices',
      emptyIcon: Icons.devices_other_rounded,
      emptyTitle: 'No devices',
      emptyMessage: 'Devices appear after a client signs in to Jellyfin.',
      onRetry: () => ref.invalidate(jellyfinDevicesProvider),
      summary: (devices) => countLabel(devices.length, 'device'),
      rowBuilder: (device) => _DeviceRow(device: device),
    );
  }
}

/// Scheduled maintenance jobs from Jellyfin's `/ScheduledTasks` endpoint.
///
/// `Run now` is not drawn: the client contract is read-only, even though the
/// design board shows the write as the eventual primary action.
class JellyfinTasksScreen extends ConsumerWidget {
  const JellyfinTasksScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    if (ref.watch(jellyfinLacksAdministratorProvider)) {
      return _needsAdministrator(context, ref, 'scheduled tasks', topPadding);
    }
    return ServiceListPage<JellyfinScheduledTask>(
      service: ServiceKey.jellyfin,
      topPadding: topPadding,
      value: ref.watch(jellyfinTasksProvider),
      serviceName: 'Jellyfin tasks',
      emptyIcon: Icons.task_alt_rounded,
      emptyTitle: 'No scheduled tasks',
      emptyMessage: 'Jellyfin returned no maintenance jobs.',
      onRetry: () => ref.invalidate(jellyfinTasksProvider),
      summary: _tasksSummary,
      rowBuilder: (task) => _TaskRow(task: task),
    );
  }
}

/// Current Jellyfin playback activity.
///
/// Jellyfin's historical `/System/ActivityLog/Entries` endpoint is not present
/// in the client contract. This tab therefore renders the real activity Cupola
/// can operate today (live sessions) through the existing Stream shell.
class JellyfinActivityScreen extends ConsumerWidget {
  const JellyfinActivityScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return _JellyfinActivityBody(topPadding: topPadding);
  }
}

class _JellyfinActivityBody extends ConsumerWidget {
  const _JellyfinActivityBody({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(jellyfinSessionsProvider);
    // The host's two bands and the status bar the upper one consumes: this
    // page has no `SafeArea` and no app bar to take the inset off first.
    final top = topPadding + MediaQuery.paddingOf(context).top;
    // The tab is this one read: a dark server is its leaf, never "Nobody is
    // watching right now".
    if (sessions.hasError && !sessions.hasValue) {
      return AmbientScaffold(
        accent: ServiceKey.jellyfin.accent,
        body: Padding(
          padding: EdgeInsets.only(top: top),
          child: ServiceOfflineState.failure(
            service: ServiceKey.jellyfin,
            error: sessions.error!,
            onRetry: () => ref.invalidate(jellyfinSessionsProvider),
          ),
        ),
      );
    }
    return AmbientScaffold(
      accent: ServiceKey.jellyfin.accent,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(jellyfinSessionsProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            0,
            top + AppSpacing.md,
            0,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            StreamNowPlayingSection(
              service: ServiceKey.jellyfin,
              sessions: sessions,
            ),
            if (ref.watch(jellyfinLacksAdministratorProvider))
              const JellyfinOwnPlaybackNote(),
          ],
        ),
      ),
    );
  }
}

bool _isConfigured(WidgetRef ref) =>
    ref.watch(currentSettingsProvider).isServiceConfigured(ServiceKey.jellyfin);

Widget _notConfigured() =>
    NotConfiguredPlaceholder.forService(ServiceKey.jellyfin);

/// The Devices and Tasks tabs on a non-administrator token: `/Devices` and
/// `/ScheduledTasks` are elevated, so the list would only ever be a refusal.
Widget _needsAdministrator(
  BuildContext context,
  WidgetRef ref,
  String what,
  double topPadding,
) => AmbientScaffold(
  accent: ServiceKey.jellyfin.accent,
  body: JellyfinAdminPlaceholder(
    what: what,
    // The host's two bands and the status bar the upper one consumes.
    topPadding: topPadding + MediaQuery.paddingOf(context).top,
    connectionId:
        ref.watch(activeInstanceProvider(ServiceKey.jellyfin))?.id ?? '',
  ),
);

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final JellyfinUserDto user;

  @override
  Widget build(BuildContext context) {
    final role = user.isAdministrator ? 'Administrator' : 'User';
    final state = user.isDisabled ? 'Disabled' : role;
    final lastActivity = user.lastActivityAt == null
        ? 'Last activity unavailable'
        : 'Last active ${formatRelativeDateTime(user.lastActivityAt!)}';
    // A role is not a state, and colour is information: an administrator's
    // row says so in its words, as every other row does, and carries no tone.
    const tone = StatusTone.neutral;
    return ServiceRecordRow(
      icon: user.isDisabled
          ? Icons.person_off_outlined
          : Icons.person_outline_rounded,
      tone: tone,
      title: user.name.trim().isEmpty ? 'Unnamed user' : user.name.trim(),
      detail: lastActivity,
      trailing: state,
      semanticLabel:
          '${user.name.trim().isEmpty ? 'Unnamed user' : user.name.trim()}, '
          '$state, $lastActivity',
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final JellyfinDevice device;

  @override
  Widget build(BuildContext context) {
    final name = device.name.trim().isEmpty ? 'Unnamed device' : device.name;
    final client = [
      device.appName.trim(),
      device.appVersion.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    final owner = device.lastUserName.trim().isEmpty
        ? 'User unavailable'
        : device.lastUserName.trim();
    final lastSeen = device.lastActivityAt == null
        ? 'Last seen unavailable'
        : 'Last seen ${formatRelativeDateTime(device.lastActivityAt!)}';
    final detail = [owner, if (client.isNotEmpty) client, lastSeen].join(' · ');
    return ServiceRecordRow(
      icon: Icons.devices_other_rounded,
      tone: StatusTone.neutral,
      title: name,
      detail: detail,
      trailing: client.isEmpty ? '—' : device.appName,
      semanticLabel:
          '$name, $owner, ${client.isEmpty ? 'client unavailable' : client}, $lastSeen',
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final JellyfinScheduledTask task;

  @override
  Widget build(BuildContext context) {
    final presentation = _taskPresentation(task);
    final started = task.lastStartedAt == null
        ? 'Last run unavailable'
        : 'Started ${formatRelativeDateTime(task.lastStartedAt!)}';
    final duration = _taskDuration(task);
    final detail = [
      started,
      ?duration,
      if (task.errorMessage.trim().isNotEmpty) task.errorMessage.trim(),
    ].join(' · ');
    final name = task.name.trim().isEmpty ? 'Unnamed task' : task.name.trim();
    return ServiceRecordRow(
      icon: presentation.icon,
      tone: presentation.tone,
      title: name,
      detail: detail,
      trailing: presentation.label,
      semanticLabel:
          '$name, ${presentation.label}, ${spokenFromDotted(detail)}',
    );
  }
}

String _usersSummary(List<JellyfinUserDto> users) {
  final disabled = users.where((user) => user.isDisabled).length;
  final suffix = disabled == 0 ? '' : ' · $disabled disabled';
  return '${countLabel(users.length, 'user')}$suffix';
}

String _tasksSummary(List<JellyfinScheduledTask> tasks) {
  final running = tasks.where((task) => task.isRunning).length;
  final suffix = running == 0 ? '' : ' · $running running';
  return '${tasks.length} scheduled$suffix';
}

({String label, StatusTone tone, IconData icon}) _taskPresentation(
  JellyfinScheduledTask task,
) {
  if (task.isRunning) {
    final progress = task.progress;
    final suffix = progress == null
        ? ''
        : ' · ${formatPercent(progress.clamp(0, 100))}';
    return (
      label: 'Running$suffix',
      tone: StatusTone.info,
      icon: Icons.sync_rounded,
    );
  }
  if (task.failed) {
    return (
      label: 'Failed',
      tone: StatusTone.warning,
      icon: Icons.warning_amber_rounded,
    );
  }
  if (task.lastStatus.toLowerCase() == 'completed') {
    return (
      label: 'Completed',
      tone: StatusTone.success,
      icon: Icons.task_alt_rounded,
    );
  }
  final label = task.state.trim().isEmpty ? 'Idle' : task.state.trim();
  return (label: label, tone: StatusTone.neutral, icon: Icons.schedule_rounded);
}

String? _taskDuration(JellyfinScheduledTask task) {
  final start = task.lastStartedAt;
  final end = task.lastEndedAt;
  if (start == null || end == null || end.isBefore(start)) return null;
  final duration = end.difference(start);
  return formatTimeSpan(duration);
}
