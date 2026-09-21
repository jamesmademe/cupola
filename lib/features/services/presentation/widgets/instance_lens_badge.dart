import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The lens: which connection this screen is looking through, and the way to
/// change it.
///
/// **Renders nothing at all while the service has one connection**, which is
/// the whole of the "you do not pay for the fold until you need it" rule. On
/// the overwhelmingly common install this widget is an empty box and the app
/// bar is the one that shipped before instances existed.
///
/// ## Why this is not the picker that was removed
///
/// The dashboard used to carry a chevron next to the title opening a list of
/// all seventeen services. The Portal replaced it and it was deleted, which is
/// what freed this spot. The two are not the same control and must not become
/// it: the Portal answers *where do I go*, this answers *which one of these am
/// I looking at*. The boundary is one rule — **this never lists another
/// service.** The day a row here points at Sonarr, the duplicate the Portal
/// just removed is back.
class InstanceLensBadge extends ConsumerWidget {
  const InstanceLensBadge({super.key, required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasMultipleInstancesProvider(service))) {
      return const SizedBox.shrink();
    }
    final active = ref.watch(activeInstanceProvider(service));
    if (active == null) return const SizedBox.shrink();

    final label = active.label.isEmpty ? active.id : active.label;

    return Semantics(
      button: true,
      container: true,
      enabled: true,
      label: 'Lens: $label',
      hint: 'changes which ${service.title} this screen reads',
      onTap: () => _showLensSheet(context, ref, service),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _showLensSheet(context, ref, service),
          borderRadius: AppRadius.borderRadiusPill,
          child: ConstrainedBox(
            // The pill is 24pt so it sits inside a 22pt title without pushing the
            // bar around; the tap target is the full bar height regardless.
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Center(
                widthFactor: 1,
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  decoration: BoxDecoration(
                    color: service.accent.withValues(alpha: 0.15),
                    borderRadius: AppRadius.borderRadiusPill,
                    border: Border.all(
                      color: service.accent.withValues(alpha: 0.40),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: AppTheme.eyebrow(service.accent),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: service.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showLensSheet(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
) {
  // Configured only. The sheet is the one control that *persists* a lens, so a
  // row here for a connection with no address is an offer to point the whole
  // app at nothing — and `select` writes to disk, so the app would come back up
  // that way at the next cold start, showing a NotConfiguredPlaceholder with
  // the working connection two centimetres away in the same sheet.
  final instances = ref
      .read(currentSettingsProvider)
      .configuredInstancesOf(service);
  final activeId = ref.read(activeInstanceProvider(service))?.id;

  return AppBottomSheet.show<void>(
    context: context,
    title: service.title,
    subtitle: instances.length == 2
        ? 'Two connections. Pick the one to read.'
        : '${instances.length} connections. Pick the one to read.',
    icon: service.icon,
    builder: (sheetContext) => _LensOptions(
      service: service,
      instances: instances,
      activeId: activeId,
    ),
  );
}

class _LensOptions extends ConsumerWidget {
  const _LensOptions({
    required this.service,
    required this.instances,
    required this.activeId,
  });

  final ServiceKey service;
  final List<ServiceInstance> instances;
  final String? activeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroupCard(
      children: [
        for (final instance in instances)
          SettingsCard.grouped(
            leading: Icon(service.icon),
            // The label is the identity; the service name is already the
            // sheet's title and repeating it in every row says nothing.
            title: instance.label.isEmpty ? instance.id : instance.label,
            // Deliberately the address rather than a reachability pip: health
            // is answered per *service* today, so a dot here would be a colour
            // this screen cannot actually stand behind.
            subtitle: service.extractHost(instance.url) ?? instance.url,
            accentColor: service.accent,
            trailing: instance.id == activeId
                ? Icon(Icons.check_rounded, color: service.accent)
                : null,
            semanticHint: instance.id == activeId
                ? 'currently being read'
                : 'reads ${service.title} through this connection instead',
            onTap: () async {
              Navigator.of(context).pop();
              if (instance.id == activeId) return;
              await ref
                  .read(activeInstancesProvider.notifier)
                  .select(service, instance.id);
            },
          ),
      ],
    );
  }
}
