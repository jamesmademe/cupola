import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One service inside a [SettingsGroupCard]: its accent icon, its host, and the
/// live state of the connection.
///
/// A healthy row shows the host and lets the glyph carry "connected"; a broken
/// one leads with the cause, because that is the only thing the user came to
/// find out. The spoken form always names the state, since the glyph and the
/// tint are the only things carrying it on screen.
class ServiceConnectionRow extends ConsumerWidget {
  const ServiceConnectionRow({
    super.key,
    required this.service,
    required this.onTap,
  });

  final ServiceKey service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.watch(currentSettingsProvider);
    final url = settings.urlFor(service);
    final host = service.extractHost(url) ?? url;

    // A Seerr account that signed out has a connection: its row reads signed
    // out from the diagnosis below, never `Not set up`.
    if (!settings.hasServiceConnection(service)) {
      final presentation = describeConnection(
        service,
        status: ServiceConnectionStatus.notConfigured,
      );
      return SettingsCard.grouped(
        leading: Icon(service.icon),
        title: service.title,
        subtitle: presentation.label,
        accentColor: service.accent,
        semanticLabel: '${service.title}, ${presentation.label}',
        semanticHint: 'sets up the ${service.title} connection',
        onTap: onTap,
        trailing: Icon(Icons.add_rounded, color: colorScheme.onSurfaceVariant),
      );
    }

    // The screen this row lives on is called Connections, and until now it
    // could only ever show one per service: a second Radarr was invisible
    // here, of all places. The count is the whole fix; the row still opens
    // the first connection's form, which is where the others are listed and
    // edited. Said only when there is more than one, the same rule the badge
    // and the lens sheet follow: a stack with a single Radarr must not grow a
    // count of one.
    final connections = settings.configuredInstancesOf(service).length;

    final asyncDiagnosis = ref.watch(serviceDiagnosisProvider(service));
    final diagnosis = asyncDiagnosis.when(
      loading: () => const ServiceDiagnosis.checking(),
      // A provider that threw tells us the same thing a failed probe does: we
      // could not confirm the service, and we cannot say why.
      error: (_, _) =>
          const ServiceDiagnosis(ServiceConnectionStatus.disconnected),
      data: (value) => value,
    );
    final presentation = describeConnection(
      service,
      status: diagnosis.status,
      reason: diagnosis.reason,
      gateway: diagnosis.gateway,
    );
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    // Line two is the setup and the address in use (J-Config-Away-States e):
    // `Home and away · radarr.example.net` follows the route without a word.
    // The setup is said once a connection anywhere has an address away;
    // before that every row would read `Home only`, a setup nobody chose.
    // Away, a connection only at home says its state instead, which says
    // the setup with it.
    //
    // The state is the worst of the service's connections, so the setup and
    // the address are that connection's too, and the row names it when it
    // is not the first: the second Radarr only at home used to read `Only at
    // home` beside the first Radarr's address, which has an address away.
    final first = settings.instancesOf(service).first;
    final subject = switch (diagnosis.connectionId) {
      final id? => settings.instanceById(id) ?? first,
      null => first,
    };
    final named =
        subject.id != first.id && settings.hasMultipleInstances(service)
        ? settings.connectionTitle(subject.id, service, joiner: ' ')
        : null;
    final inUse =
        service.extractHost(
          ref.watch(connectionReachProvider(subject.id))?.url ?? subject.url,
        ) ??
        host;
    final onlyAtHome = diagnosis.reason == ServiceFailureReason.onlyAtHome;
    // Neither address answered: the state says the setup and both places,
    // and no address is in use to name.
    final atBoth = diagnosis.reason == ServiceFailureReason.unreachableAtBoth;
    final setup = onlyAtHome || !settings.instances.any((i) => i.away != null)
        ? null
        : subject.away != null
        ? Lexicon.homeAndAway
        : Lexicon.homeOnly;
    final where = atBoth ? null : [?setup, inUse].join(dotSeparator);
    final hostLine = [
      ?where,
      if (settings.hasMultipleInstances(service)) '$connections connections',
    ].join(dotSeparator);
    final said = atBoth
        ? '${presentation.label} at home or away'
        : presentation.label;
    final state = [?named, said].join(dotSeparator);

    return SettingsCard.grouped(
      leading: Icon(service.icon),
      title: service.title,
      // Connected: the host is the useful line and the glyph says the rest.
      // Broken: the cause comes first, with the host still there to check.
      subtitle: presentation.needsAttention
          ? [state, if (hostLine.isNotEmpty) hostLine].join(dotSeparator)
          : hostLine,
      subtitleLeading: _StatusGlyph(
        presentation: presentation,
        color: toneColor,
        checking: diagnosis.status == ServiceConnectionStatus.checking,
      ),
      subtitleColor: presentation.needsAttention ? toneColor : null,
      accentColor: service.accent,
      semanticLabel: [
        service.title,
        state,
        if (!atBoth) ...[?setup, inUse],
        if (settings.hasMultipleInstances(service)) '$connections connections',
      ].join(', '),
      // "Connection settings", not "settings": the service's own settings are
      // a different page, and the hint is the only thing a screen reader has
      // to tell the two apart.
      semanticHint: 'opens the ${service.title} connection settings',
      onTap: onTap,
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({
    required this.presentation,
    required this.color,
    required this.checking,
  });

  final ConnectionPresentation presentation;
  final Color color;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Icon(presentation.icon, size: 16, color: color);
  }
}
