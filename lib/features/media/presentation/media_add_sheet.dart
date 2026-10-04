import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Adds a film nobody holds to Radarr: which Radarr, the quality
/// profile and root folder it lands under, whether Radarr monitors it, and
/// whether it searches now.
///
/// [connections] are the Radarr connections set up, the first chosen. The
/// sheet resolves to the one the film was added to, null when it closed
/// without adding. The film is posted as that Radarr looks it up
/// ([mediaAddLookupProvider]), with the form the global search's add uses
/// ([arrAddFormProvider]).
Future<ServiceInstance?> showMediaAddSheet(
  BuildContext context, {
  required int tmdbId,
  required List<ServiceInstance> connections,
  required String Function(ServiceInstance connection) name,
  required String title,
  String? year,
  TitleLight? light,
}) {
  assert(connections.isNotEmpty, 'nothing to add to');
  return AppBottomSheet.show<ServiceInstance>(
    context: context,
    // One Radarr: the sheet names it. More: the pills under it do.
    title:
        'Add to ${connections.length == 1 ? name(connections.single) : ServiceKey.radarr.title}',
    subtitle: (year ?? '').isEmpty ? title : '$title · $year',
    showClose: true,
    builder: (_) => MediaAddSheet(
      tmdbId: tmdbId,
      connections: connections,
      name: name,
      light: light,
    ),
  );
}

/// The body of the add sheet, under its header: [showMediaAddSheet] opens it.
class MediaAddSheet extends ConsumerStatefulWidget {
  const MediaAddSheet({
    super.key,
    required this.tmdbId,
    required this.connections,
    required this.name,
    this.light,
  });

  final int tmdbId;
  final List<ServiceInstance> connections;
  final String Function(ServiceInstance connection) name;
  final TitleLight? light;

  @override
  ConsumerState<MediaAddSheet> createState() => _MediaAddSheetState();
}

class _MediaAddSheetState extends ConsumerState<MediaAddSheet> {
  late ServiceInstance _to = widget.connections.first;

  ArrAddArgs get _args => (instanceId: _to.id, service: ServiceKey.radarr);

  ({String connectionId, int tmdbId}) get _target =>
      (connectionId: _to.id, tmdbId: widget.tmdbId);

  Future<void> _add(ArrAddFormNotifier form, ArrAddRequest request) async {
    final to = _to;
    final refused = await form.submit(request);
    if (refused == null && mounted) Navigator.of(context).pop(to);
  }

  Future<void> _pickProfile(ArrAddFormState state) async {
    final current = state.profiles.where((p) => p.id == state.profileId);
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: state.profileId,
      currentLabel: current.firstOrNull?.name ?? '',
      options: [
        for (final profile in state.profiles)
          MediaDetailValueOption(value: profile.id, label: profile.name),
      ],
    );
    if (picked != null) {
      ref.read(arrAddFormProvider(_args).notifier).selectProfile(picked.value);
    }
  }

  Future<void> _pickFolder(ArrAddFormState state) async {
    final picked = await showMediaValueSheet<String>(
      context,
      title: 'Root folder',
      value: state.rootFolder,
      currentLabel: state.rootFolder ?? '',
      options: [
        for (final folder in state.rootFolders)
          MediaDetailValueOption(value: folder, label: folder),
      ],
    );
    if (picked != null) {
      ref
          .read(arrAddFormProvider(_args).notifier)
          .selectRootFolder(picked.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final name = widget.name(_to);
    final state = ref.watch(arrAddFormProvider(_args));
    final form = ref.read(arrAddFormProvider(_args).notifier);
    final lookup = ref.watch(mediaAddLookupProvider(_target));
    final profile = state.profiles
        .where((p) => p.id == state.profileId)
        .firstOrNull
        ?.name;
    final monitor = state.monitored;
    final search = monitor && state.searchOnAdd;
    final indexers = switch (state.searchingIndexers) {
      null => 'your indexers',
      1 => 'your indexer',
      final count => 'your $count indexers',
    };
    final loaded = !state.isLoading && state.profiles.isNotEmpty;

    final Widget body = switch (lookup) {
      AsyncError(:final error) => InlineErrorRetry(
        message: 'Could not look it up in $name',
        error: error,
        service: ServiceKey.radarr,
        instanceId: _to.id,
        onRetry: () => ref.invalidate(mediaAddLookupProvider(_target)),
      ),
      _ when state.isLoading || lookup.isLoading => const ShimmerPlaceholder(
        height: 4 * 60,
      ),
      // The options did not load: the sentence the form wrote, and why.
      _ when !loaded => _Refusal(state: state),
      _ => MediaGroup(
        children: [
          _ValueRow(
            label: 'Quality profile',
            value: Text(
              profile ?? '',
              textAlign: TextAlign.end,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            onTap: state.profiles.length > 1 ? () => _pickProfile(state) : null,
          ),
          _ValueRow(
            label: 'Root folder',
            value: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  state.rootFolder ?? '',
                  textAlign: TextAlign.end,
                  style: AppType.mono.copyWith(color: room.inkSecondary),
                ),
                if (state.freeSpace[state.rootFolder] case final free?)
                  Text(
                    '${formatBytes(free)} free',
                    style: AppType.caption.copyWith(color: room.inkTertiary),
                  ),
              ],
            ),
            onTap: state.rootFolders.length > 1
                ? () => _pickFolder(state)
                : null,
          ),
          _SwitchRow(
            label: 'Monitor',
            detail: monitor
                ? 'Grabs it and upgrades it to ${profile ?? 'its profile'}'
                : '$name lists it and never looks for it',
            value: monitor,
            onChanged: (value) {
              form.setMonitored(value);
              // Radarr does not search for a film it does not monitor.
              form.setSearchOnAdd(value);
            },
          ),
          _SwitchRow(
            label: 'Search when added',
            detail: !monitor
                ? 'Needs Monitor on'
                : search
                ? 'Asks $indexers right away'
                : 'Search later from its page',
            value: search,
            onChanged: monitor ? form.setSearchOnAdd : null,
          ),
        ],
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.connections.length > 1) ...[
          Text(
            'Instance',
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectionPills<ServiceInstance>.wrap(
            values: widget.connections,
            selected: _to,
            labelBuilder: widget.name,
            onSelected: (connection) => setState(() => _to = connection),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        body,
        // A post that failed: its sentence, and why, over the button.
        if (loaded && state.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Refusal(state: state),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: state.canSubmit && lookup.hasValue
              ? () => _add(
                  form,
                  RadarrAddRequest(instanceId: _to.id, movie: lookup.value!),
                )
              : null,
          style: mediaLeadStyle(context, widget.light),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.isSubmitting)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.add_rounded, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(search ? 'Add and search' : 'Add to $name')),
            ],
          ),
        ),
      ],
    );
  }
}

/// A setting and its value, on the right; tapped to change it when there is
/// more than one to choose from.
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.onTap});

  final String label;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Text(label, style: AppType.row.copyWith(color: room.ink)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: room.inkTertiary,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return MergeSemantics(child: row);
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// A setting that is on or off, with what that means under it.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppType.row.copyWith(color: room.ink)),
                    Text(
                      detail,
                      style: AppType.meta
                          .weight(FontWeight.w400)
                          .copyWith(color: room.inkTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the form could not do: its sentence, and why under it.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.state});

  final ArrAddFormState state;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.error ?? '',
          // Amber unless the server did not answer: a refusal is a fault.
          style: AppType.row.copyWith(
            color: statusToneColor(
              Theme.of(context).colorScheme,
              surface: room.raised,
              switch (state.errorReason) {
                final reason? => failureTone(reason),
                null => StatusTone.warning,
              },
            ),
          ),
        ),
        if ((state.errorDetail ?? '').isNotEmpty)
          Text(
            state.errorDetail!,
            style: AppType.meta
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
      ],
    );
  }
}
