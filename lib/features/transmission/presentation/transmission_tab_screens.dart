import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_actions.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// The first Transmission RPC revision with `labels`, on `torrent-get` and
/// `torrent-set` alike: 16, shipped in Transmission 3.00.
const int _labelsRpcVersion = 16;

/// Labels are properties of torrents in Transmission, not records in a label
/// registry. This page therefore filters and edits the loaded torrent list; it
/// never invents an empty label after its last torrent stops carrying it.
class TransmissionLabelsScreen extends ConsumerStatefulWidget {
  const TransmissionLabelsScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<TransmissionLabelsScreen> createState() =>
      _TransmissionLabelsScreenState();
}

class _TransmissionLabelsScreenState
    extends ConsumerState<TransmissionLabelsScreen> {
  String? _selectedLabel;

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.transmission),
      ),
    );
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.transmission);
    }

    final torrents = ref.watch(transmissionTorrentsProvider);
    final session = ref.watch(transmissionSessionProvider);

    return AmbientScaffold(
      accent: ServiceKey.transmission.accent,
      body: Padding(
        padding: EdgeInsets.only(top: widget.topPadding),
        child: AsyncValueWidget<List<TransmissionTorrent>>(
          value: torrents,
          serviceName: 'Transmission labels',
          loadingLabel: 'Loading Transmission labels',
          onRetry: () => ref.invalidate(transmissionTorrentsProvider),
          skeleton: const ListRowsShimmer(count: 6),
          isEmpty: (items) => items.isEmpty,
          emptyBuilder: AppEmptyStatePage(
            emptyState: AppEmptyState(
              icon: Icons.label_off_outlined,
              title: 'No torrents to label',
              message: 'Labels can be assigned after a torrent is added.',
              accentColor: ServiceKey.transmission.accent,
            ),
          ),
          data: (items) => _labelsBody(context, items, session),
        ),
      ),
    );
  }

  Widget _labelsBody(
    BuildContext context,
    List<TransmissionTorrent> torrents,
    AsyncValue<TransmissionSession> session,
  ) {
    final tallies = transmissionLabelTallies(torrents);
    final labels = tallies.map((item) => item.label).toList(growable: false);
    final selected = labels.contains(_selectedLabel) ? _selectedLabel : null;
    final visible = selected == null
        ? torrents
        : torrents
              .where(
                (torrent) =>
                    torrent.labels.any((label) => label.trim() == selected),
              )
              .toList(growable: false);
    final rpcVersion = session.asData?.value.rpcVersion;
    // **16, not 17.** `labels` arrived in Transmission 3.00 — rpc-version 16 —
    // on both halves of the protocol at once: the same revision that puts
    // `labels` on `torrent-get` accepts it on `torrent-set`. Gating the editor
    // at 17 withheld it from every 3.x daemon while the rows beside the button
    // were reading and displaying the labels it claimed the daemon could not
    // write, which is not a capability split the protocol has.
    final canEdit = rpcVersion != null && rpcVersion >= _labelsRpcVersion;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(transmissionTorrentsProvider);
        ref.invalidate(transmissionSessionProvider);
        ref.invalidate(transmissionLabelsProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          if (session.hasError)
            InlineErrorRetry(
              message:
                  'Labels loaded, but the daemon capability did not. Editing is withheld.',
              onRetry: () => ref.invalidate(transmissionSessionProvider),
            )
          else if (rpcVersion != null && rpcVersion < _labelsRpcVersion)
            const _LabelsCapabilityNote(),
          SectionHeader(
            title: 'Labels',
            subtitle: tallies.isEmpty
                ? 'None in use'
                : '${tallies.length} in use',
            showChevron: false,
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectionPills<String?>(
            values: [null, ...labels],
            selected: selected,
            labelBuilder: (label) {
              if (label == null) return 'All · ${torrents.length}';
              final count = tallies
                  .firstWhere((item) => item.label == label)
                  .count;
              return '$label · $count';
            },
            onSelected: (label) => setState(() => _selectedLabel = label),
            accent: ServiceKey.transmission.accent,
          ),
          SectionHeader(
            title: 'Torrents',
            subtitle: selected == null
                ? '${torrents.length}'
                : '${visible.length} of ${torrents.length}',
            showChevron: false,
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: visible.isEmpty
                ? const AppEmptyState.inline(
                    icon: Icons.filter_alt_off_rounded,
                    title: 'No matching torrents',
                  )
                : Column(
                    children: [
                      for (var index = 0; index < visible.length; index++) ...[
                        _TorrentLabelsRow(
                          torrent: visible[index],
                          canEdit: canEdit,
                          onEdit: () => _editLabels(visible[index]),
                        ),
                        if (index != visible.length - 1)
                          const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLabels(TransmissionTorrent torrent) async {
    final labels = await _showLabelsDialog(context, torrent);
    if (labels == null || !mounted) return;

    await runTransmissionAction(
      context,
      ref,
      action: (client) => client.setLabels([torrent.rpcId], labels),
      successMessage: labels.isEmpty ? 'Labels cleared' : 'Labels updated',
      failureMessage: 'Failed to update labels',
      invalidate: <ProviderOrFamily>[
        transmissionTorrentsProvider,
        transmissionLabelsProvider,
      ],
    );
  }
}

class _LabelsCapabilityNote extends StatelessWidget {
  const _LabelsCapabilityNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(
      theme.colorScheme,
      StatusTone.info,
      surface: theme.colorScheme.surfaceContainer,
    );
    const message =
        'This daemon does not support labels. Transmission 3.0 '
        '(RPC $_labelsRpcVersion) or newer can read and assign them.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Semantics(
        container: true,
        label: message,
        child: ExcludeSemantics(
          child: AppCard.outlined(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(message, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TorrentLabelsRow extends StatelessWidget {
  const _TorrentLabelsRow({
    required this.torrent,
    required this.canEdit,
    required this.onEdit,
  });

  final TransmissionTorrent torrent;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = torrent.labels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    final labelSentence = labels.isEmpty ? 'No labels' : labels.join(', ');

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${torrent.name}, $labelSentence',
      child: AppCard.outlined(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.sell_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      torrent.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (labels.isEmpty)
                      Text(
                        'No labels',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: CupolaThemeColors.of(context).dimText,
                        ),
                      )
                    else
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final label in labels) TagChip(text: label),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                key: ValueKey('transmission-labels-edit-${torrent.rpcId}'),
                onPressed: onEdit,
                tooltip: 'Edit labels for ${torrent.name}',
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<List<String>?> _showLabelsDialog(
  BuildContext context,
  TransmissionTorrent torrent,
) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _LabelsDialog(torrent: torrent),
  );
}

class _LabelsDialog extends StatefulWidget {
  const _LabelsDialog({required this.torrent});

  final TransmissionTorrent torrent;

  @override
  State<_LabelsDialog> createState() => _LabelsDialogState();
}

class _LabelsDialogState extends State<_LabelsDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.torrent.labels.join('\n'),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Labels for ${widget.torrent.name}'),
      content: TextField(
        key: const ValueKey('transmission-labels-field'),
        controller: _controller,
        autofocus: true,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(
          labelText: 'Labels',
          helperText: 'One label per line',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_normaliseLabels(_controller.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

List<String> _normaliseLabels(String value) {
  final labels = <String>[];
  final seen = <String>{};
  for (final line in value.split('\n')) {
    final label = line.trim();
    if (label.isEmpty || !seen.add(label)) continue;
    labels.add(label);
  }
  return labels;
}

/// The writable subset of `session-get`/`session-set` represented by the
/// current Transmission client. Port testing remains deliberately absent
/// because the contract exposes no method for it.
class TransmissionSessionScreen extends ConsumerWidget {
  const TransmissionSessionScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.transmission),
      ),
    );
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.transmission);
    }

    final session = ref.watch(transmissionSessionProvider);
    return AmbientScaffold(
      accent: ServiceKey.transmission.accent,
      body: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: AsyncValueWidget<TransmissionSession>(
          value: session,
          serviceName: 'Transmission session',
          loadingLabel: 'Loading Transmission session settings',
          onRetry: () => ref.invalidate(transmissionSessionProvider),
          skeleton: const ListRowsShimmer(count: 8),
          data: (value) => _TransmissionSessionBody(session: value),
        ),
      ),
    );
  }
}

class _TransmissionSessionBody extends ConsumerStatefulWidget {
  const _TransmissionSessionBody({required this.session});

  final TransmissionSession session;

  @override
  ConsumerState<_TransmissionSessionBody> createState() =>
      _TransmissionSessionBodyState();
}

class _TransmissionSessionBodyState
    extends ConsumerState<_TransmissionSessionBody> {
  bool _saving = false;

  TransmissionSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(transmissionSessionProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _DaemonCard(session: session),
          if (_saving) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: 'Saving Transmission session settings',
              child: const LinearProgressIndicator(),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _SettingsSection(
            title: 'Connection',
            children: [
              _valueRow(
                icon: Icons.router_outlined,
                title: 'Peer port',
                value: _figure(session.peerPort),
                hint: 'edits the peer port',
                onTap: () => _editInt(
                  title: 'Peer port',
                  current: session.peerPort,
                  min: 1,
                  max: 65535,
                  onSave: (value) => _write(
                    (client) => client.setSessionPreferences(peerPort: value),
                    successMessage: 'Peer port updated',
                  ),
                ),
              ),
              _toggleRow(
                icon: Icons.shuffle_rounded,
                title: 'Random port on start',
                value: session.peerPortRandomOnStart,
                onChanged: (value) => _write(
                  (client) => client.setSessionPreferences(
                    peerPortRandomOnStart: value,
                  ),
                  successMessage: 'Random port preference updated',
                ),
              ),
              _toggleRow(
                icon: Icons.device_hub_outlined,
                title: 'Port forwarding',
                value: session.portForwardingEnabled,
                onChanged: (value) => _write(
                  (client) => client.setSessionPreferences(
                    portForwardingEnabled: value,
                  ),
                  successMessage: 'Port forwarding preference updated',
                ),
              ),
              _valueRow(
                icon: Icons.lock_outline_rounded,
                title: 'Encryption',
                value: _displayEncryption(session.encryption),
                hint: 'edits peer encryption',
                onTap: _editEncryption,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsSection(
            title: 'Peers',
            children: [
              _valueRow(
                icon: Icons.groups_outlined,
                title: 'Global peer limit',
                value: _figure(session.peerLimitGlobal),
                hint: 'edits the global peer limit',
                onTap: () => _editInt(
                  title: 'Global peer limit',
                  current: session.peerLimitGlobal,
                  min: 1,
                  onSave: (value) => _write(
                    (client) =>
                        client.setSessionPreferences(peerLimitGlobal: value),
                    successMessage: 'Global peer limit updated',
                  ),
                ),
              ),
              _valueRow(
                icon: Icons.group_outlined,
                title: 'Per-torrent peer limit',
                value: _figure(session.peerLimitPerTorrent),
                hint: 'edits the per-torrent peer limit',
                onTap: () => _editInt(
                  title: 'Per-torrent peer limit',
                  current: session.peerLimitPerTorrent,
                  min: 1,
                  onSave: (value) => _write(
                    (client) => client.setSessionPreferences(
                      peerLimitPerTorrent: value,
                    ),
                    successMessage: 'Per-torrent peer limit updated',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsSection(
            title: 'Seeding',
            children: [
              _toggleRow(
                icon: Icons.percent_rounded,
                title: 'Stop at ratio',
                value: session.seedRatioLimited,
                subtitle: session.seedRatioLimited
                    ? 'Ratio ${_ratio(session.seedRatioLimit)}'
                    : null,
                onChanged: (value) => _write(
                  (client) =>
                      client.setSessionPreferences(seedRatioLimited: value),
                  successMessage: 'Seed ratio preference updated',
                ),
              ),
              _valueRow(
                icon: Icons.balance_rounded,
                title: 'Seed ratio limit',
                value: _ratio(session.seedRatioLimit),
                hint: 'edits the seed ratio limit',
                onTap: () => _editDouble(
                  title: 'Seed ratio limit',
                  current: session.seedRatioLimit,
                  min: 0,
                  onSave: (value) => _write(
                    (client) =>
                        client.setSessionPreferences(seedRatioLimit: value),
                    successMessage: 'Seed ratio limit updated',
                  ),
                ),
              ),
              _toggleRow(
                icon: Icons.timer_outlined,
                title: 'Stop after idle time',
                value: session.idleSeedingLimitEnabled,
                subtitle: session.idleSeedingLimitEnabled
                    ? _figure(session.idleSeedingLimitMinutes, unit: 'min')
                    : null,
                onChanged: (value) => _write(
                  (client) => client.setSessionPreferences(
                    idleSeedingLimitEnabled: value,
                  ),
                  successMessage: 'Idle seeding preference updated',
                ),
              ),
              _valueRow(
                icon: Icons.schedule_rounded,
                title: 'Idle seeding limit',
                value: _figure(session.idleSeedingLimitMinutes, unit: 'min'),
                hint: 'edits the idle seeding limit',
                onTap: () => _editInt(
                  title: 'Idle seeding limit in minutes',
                  current: session.idleSeedingLimitMinutes,
                  min: 1,
                  onSave: (value) => _write(
                    (client) => client.setSessionPreferences(
                      idleSeedingLimitMinutes: value,
                    ),
                    successMessage: 'Idle seeding limit updated',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsSection(
            title: 'Queues',
            children: [
              _toggleRow(
                icon: Icons.download_outlined,
                title: 'Download queue',
                value: session.downloadQueueEnabled,
                subtitle: session.downloadQueueEnabled
                    ? _figure(session.downloadQueueSize, unit: 'active')
                    : null,
                onChanged: (value) => _write(
                  (client) =>
                      client.setSessionPreferences(downloadQueueEnabled: value),
                  successMessage: 'Download queue preference updated',
                ),
              ),
              _valueRow(
                icon: Icons.format_list_numbered_rounded,
                title: 'Download queue size',
                value: _figure(session.downloadQueueSize),
                hint: 'edits the download queue size',
                onTap: () => _editInt(
                  title: 'Download queue size',
                  current: session.downloadQueueSize,
                  min: 1,
                  onSave: (value) => _write(
                    (client) =>
                        client.setSessionPreferences(downloadQueueSize: value),
                    successMessage: 'Download queue size updated',
                  ),
                ),
              ),
              _toggleRow(
                icon: Icons.upload_outlined,
                title: 'Seed queue',
                value: session.seedQueueEnabled,
                subtitle: session.seedQueueEnabled
                    ? _figure(session.seedQueueSize, unit: 'active')
                    : null,
                onChanged: (value) => _write(
                  (client) =>
                      client.setSessionPreferences(seedQueueEnabled: value),
                  successMessage: 'Seed queue preference updated',
                ),
              ),
              _valueRow(
                icon: Icons.format_list_numbered_rounded,
                title: 'Seed queue size',
                value: _figure(session.seedQueueSize),
                hint: 'edits the seed queue size',
                onTap: () => _editInt(
                  title: 'Seed queue size',
                  current: session.seedQueueSize,
                  min: 1,
                  onSave: (value) => _write(
                    (client) =>
                        client.setSessionPreferences(seedQueueSize: value),
                    successMessage: 'Seed queue size updated',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsSection(
            title: 'Behaviour',
            children: [
              _toggleRow(
                icon: Icons.play_arrow_rounded,
                title: 'Start added torrents',
                value: session.startAddedTorrents,
                onChanged: (value) => _write(
                  (client) =>
                      client.setSessionPreferences(startAddedTorrents: value),
                  successMessage: 'Start preference updated',
                ),
              ),
              _toggleRow(
                icon: Icons.drive_file_rename_outline_rounded,
                title: 'Rename partial files',
                value: session.renamePartialFiles,
                onChanged: (value) => _write(
                  (client) =>
                      client.setSessionPreferences(renamePartialFiles: value),
                  successMessage: 'Partial-file preference updated',
                ),
              ),
              _valueRow(
                icon: Icons.memory_rounded,
                title: 'Cache size',
                value: _figure(session.cacheSizeMb, unit: 'MB'),
                hint: 'edits the cache size',
                onTap: () => _editInt(
                  title: 'Cache size in MB',
                  current: session.cacheSizeMb,
                  min: 0,
                  onSave: (value) => _write(
                    (client) =>
                        client.setSessionPreferences(cacheSizeMb: value),
                    successMessage: 'Cache size updated',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _SettingsSection(
            title: 'Blocklist',
            children: [
              _toggleRow(
                icon: Icons.shield_outlined,
                title: 'Use blocklist',
                value: session.blocklistEnabled,
                onChanged: (value) => _write(
                  (client) =>
                      client.setSessionPreferences(blocklistEnabled: value),
                  successMessage: 'Blocklist preference updated',
                ),
              ),
              _valueRow(
                icon: Icons.rule_rounded,
                title: 'Rules reported',
                value: _figure(session.blocklistSize),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
  }) {
    return _SessionToggleRow(
      icon: icon,
      title: title,
      value: value,
      subtitle: subtitle,
      enabled: !_saving,
      onChanged: onChanged,
    );
  }

  Widget _valueRow({
    required IconData icon,
    required String title,
    required String value,
    String? hint,
    VoidCallback? onTap,
  }) {
    return _SessionValueRow(
      icon: icon,
      title: title,
      value: value,
      hint: hint,
      onTap: _saving ? null : onTap,
    );
  }

  Future<void> _write(
    Future<void> Function(TransmissionClient client) action, {
    required String successMessage,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    await runTransmissionAction(
      context,
      ref,
      action: action,
      successMessage: successMessage,
      failureMessage: 'Failed to update Transmission session',
      invalidate: <ProviderOrFamily>[
        transmissionSessionProvider,
        transmissionSessionFactsProvider,
        transmissionFreeSpaceProvider,
      ],
    );
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _editInt({
    required String title,
    required int? current,
    required int min,
    int? max,
    // `Future<void> Function`, not `ValueChanged`: every caller hands back a
    // `_write`, and firing that and forgetting it left `_saving` flipping back
    // before the request had answered.
    required Future<void> Function(int value) onSave,
  }) async {
    final value = await _showNumberDialog<int>(
      context,
      title: title,
      current: current?.toString() ?? '',
      parse: int.tryParse,
      valid: (value) => value >= min && (max == null || value <= max),
      range: max == null ? '$min or more' : '$min–$max',
    );
    if (value != null && mounted) await onSave(value);
  }

  Future<void> _editDouble({
    required String title,
    required double? current,
    required double min,
    required Future<void> Function(double value) onSave,
  }) async {
    final value = await _showNumberDialog<double>(
      context,
      title: title,
      current: current?.toString() ?? '',
      parse: double.tryParse,
      valid: (value) => value.isFinite && value >= min,
      range: '$min or more',
      decimal: true,
    );
    if (value != null && mounted) await onSave(value);
  }

  Future<void> _editEncryption() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Peer encryption'),
        children: [
          for (final value in const ['required', 'preferred', 'tolerated'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Text(_displayEncryption(value)),
            ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    await _write(
      (client) => client.setSessionPreferences(encryption: value),
      successMessage: 'Encryption preference updated',
    );
  }
}

class _DaemonCard extends StatelessWidget {
  const _DaemonCard({required this.session});

  final TransmissionSession session;

  @override
  Widget build(BuildContext context) {
    final version = session.version.trim().isEmpty
        ? '—'
        : session.version.trim();
    final rpc = _figure(session.rpcVersion);
    return Semantics(
      container: true,
      label: 'Transmission version $version, RPC version $rpc',
      child: ExcludeSemantics(
        child: AppCard.filled(
          accentColor: ServiceKey.transmission.accent,
          child: Row(
            children: [
              const Icon(Icons.settings_ethernet_rounded),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Transmission $version',
                  style: AppTheme.rowTitle(Theme.of(context).brightness),
                ),
              ),
              Text(
                'RPC $rpc',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.weight(FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(title: title, showChevron: false),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(children: children),
    ],
  );
}

class _SessionValueRow extends StatelessWidget {
  const _SessionValueRow({
    required this.icon,
    required this.title,
    required this.value,
    this.hint,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onTap != null,
      label: '$title, $value',
      hint: onTap == null ? null : hint,
      onTap: onTap,
      child: ExcludeSemantics(
        child: SettingsCard.grouped(
          leading: Icon(icon),
          title: title,
          trailing: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.weight(FontWeight.w700),
          ),
          onTap: onTap,
          accentColor: ServiceKey.transmission.accent,
        ),
      ),
    );
  }
}

class _SessionToggleRow extends StatelessWidget {
  const _SessionToggleRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final state = value ? 'On' : 'Off';
    final spoken = [title, state, ?subtitle].join(', ');
    final activate = enabled ? () => onChanged(!value) : null;
    return Semantics(
      container: true,
      enabled: enabled,
      toggled: value,
      label: spoken,
      hint: enabled ? 'toggles $title' : 'saving another setting',
      onTap: activate,
      child: ExcludeSemantics(
        child: SettingsCard.grouped(
          leading: Icon(icon),
          title: title,
          subtitle: subtitle,
          trailing: IgnorePointer(
            child: Switch(value: value, onChanged: enabled ? onChanged : null),
          ),
          onTap: activate,
          accentColor: ServiceKey.transmission.accent,
        ),
      ),
    );
  }
}

Future<T?> _showNumberDialog<T extends num>(
  BuildContext context, {
  required String title,
  required String current,
  required T? Function(String value) parse,
  required bool Function(T value) valid,
  required String range,
  bool decimal = false,
}) async {
  final controller = TextEditingController(text: current);
  String? error;
  final result = await showDialog<T>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('transmission-session-number-field'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: InputDecoration(
            labelText: title,
            helperText: 'Accepted range: $range',
            errorText: error,
          ),
          onSubmitted: (_) {
            final value = parse(controller.text.trim());
            if (value != null && valid(value)) {
              Navigator.of(dialogContext).pop(value);
            } else {
              setDialogState(() => error = 'Enter a value in range');
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = parse(controller.text.trim());
              if (value == null || !valid(value)) {
                setDialogState(() => error = 'Enter a value in range');
                return;
              }
              Navigator.of(dialogContext).pop(value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  controller.dispose();
  return result;
}

String _displayEncryption(String value) {
  final normalised = value.trim().toLowerCase();
  if (normalised.isEmpty) return '—';
  return '${normalised[0].toUpperCase()}${normalised.substring(1)}';
}

/// A figure the daemon reported, or an em dash when it did not report one.
///
/// **Zero is a value, not an absence.** `session-get` on an old daemon simply
/// omits fields it does not know, and `parseInt` used to answer that with 0 —
/// so "Cache size 0 MB" was indistinguishable from a cache the user had
/// switched off, and both were stated as fact.
String _figure(num? value, {String? unit}) {
  if (value == null) return '—';
  return unit == null ? '$value' : '$value $unit';
}

/// A seed ratio to two places, or an em dash when the daemon has no opinion.
String _ratio(double? value) => value == null ? '—' : value.toStringAsFixed(2);
