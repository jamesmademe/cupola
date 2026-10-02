@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/capability_copy.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/capability_overrides.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

// One connection per answer a probe can give.
const _readWrite = 'rw';
const _readOnly = 'ro';
const _unanswered = 'unanswered';

/// A thing and the word under it, so a pair of states reads side by side.
Widget _labelled(String label, Widget child) => Builder(
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: AppSpacing.xs),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  ),
);

Widget _row(List<Widget> children) =>
    Wrap(spacing: 32, runSpacing: 16, children: children);

/// The Dashboard decision's trailing button, as `dashboard_sections.dart`
/// styles it.
Widget _decisionButton(
  BuildContext context,
  String label,
  VoidCallback onPressed,
  Widget Function(Widget) annotate,
) => TextButton(
  onPressed: onPressed,
  style: TextButton.styleFrom(
    foregroundColor: Theme.of(context).colorScheme.primary,
    minimumSize: const Size(56, 44),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
  ),
  child: annotate(Text(label, maxLines: 1)),
);

Widget _openIn(ServiceKey target) => CrossServiceAction.builder(
  target: target,
  blockedMessage: 'Connect ${target.title} to open this movie',
  onTap: () {},
  builder: (context, onPressed, annotate) => HeaderActionButton(
    icon: Icons.open_in_new_rounded,
    label: 'Open',
    semanticLabel: 'Open in ${target.title}',
    onPressed: onPressed,
    annotate: annotate,
  ),
);

Widget _openTransfer(ServiceKey target) => CrossServiceAction.builder(
  target: target,
  blockedMessage: 'Connect ${target.title} to open this transfer.',
  onTap: () {},
  builder: (context, onPressed, annotate) =>
      _decisionButton(context, 'Open in ${target.title}', onPressed, annotate),
);

Widget _glyphCell(ServiceKey target) => CrossServiceAction(
  target: target,
  label: 'Open in ${target.title}',
  blockedMessage: 'Connect ${target.title} to open this transfer.',
  onTap: () {},
  child: const Icon(Icons.open_in_new_rounded),
);

Widget _vmButton(String connectionId) => CapabilityGatedAction.icon(
  service: ServiceKey.unraid,
  connectionId: connectionId,
  resource: 'vms',
  hint: 'requires a key that can write VMs',
  blockedMessage: 'This Unraid key can\'t start or stop VMs.',
  tooltip: 'Start Kodi',
  onTap: () {},
  icon: const Icon(Icons.play_arrow_rounded),
);

Widget _toggle(String connectionId) => CapabilityGatedAction.toggle(
  service: ServiceKey.truenas,
  connectionId: connectionId,
  resource: 'sharing',
  hint: 'requires a TrueNAS key with write access',
  blockedMessage: 'This TrueNAS key can\'t change shares.',
  value: true,
  onChanged: (_) {},
);

Widget _save(String connectionId) => CapabilityGatedAction.builder(
  service: ServiceKey.nginxProxyManager,
  connectionId: connectionId,
  resource: 'proxy_hosts',
  hint: 'requires an admin account',
  blockedMessage:
      'This Nginx Proxy Manager account can\'t change proxy hosts. Sign in '
      'as an admin to change this.',
  onTap: () {},
  builder: (context, onPressed, annotate) =>
      FilledButton(onPressed: onPressed, child: annotate(const Text('Save'))),
);

/// Manage on a title's page, as the gate of its Seerr says.
Widget _manage(GateVerdict verdict) => RoleGatedAction.builder(
  verdict: verdict,
  onTap: () {},
  builder: (context, onPressed, annotate) => HeaderActionButton(
    icon: Icons.settings_outlined,
    label: 'Manage',
    semanticLabel: 'Manage movie',
    onPressed: onPressed,
    annotate: annotate,
  ),
);

/// A popup menu's panel, drawn in place: an open menu is a route of its own
/// and paints above the page, outside any one scene.
Widget _menu(String connectionId) => Builder(
  builder: (context) {
    final theme = Theme.of(context);
    final menu = theme.popupMenuTheme;
    return Material(
      color: menu.color ?? theme.colorScheme.surfaceContainer,
      elevation: menu.elevation ?? 3,
      shape:
          menu.shape ??
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: IntrinsicWidth(
          child: Semantics(
            role: SemanticsRole.menu,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PopupMenuItem<String>(
                  value: 'disable',
                  child: CapabilityGatedMenuLabel(
                    service: ServiceKey.nginxProxyManager,
                    connectionId: connectionId,
                    resource: 'proxy_hosts',
                    text: 'Disable…',
                    hint: 'requires an admin account',
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'advanced',
                  child: Text('Advanced Nginx config…'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  },
);

/// Raises the toast a blocked tap raises, through the same helper, inside a
/// scaffold of the scene's own so it lands in the picture.
class _Toast extends StatefulWidget {
  const _Toast(this.message, this.action);

  final String message;
  final String action;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SnackBarHelper.withAction(
        context,
        widget.message,
        actionLabel: widget.action,
        onAction: () {},
        // Held for the length of the render; live it is four seconds.
        duration: const Duration(minutes: 1),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

CatalogScene _toastScene(
  String caption,
  String message,
  String action, {
  double height = 104,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => ScaffoldMessenger(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: _Toast(message, action),
    ),
  ),
  width: 390,
  height: height,
  textScale: textScale,
);

void main() {
  catalogCard(
    'CrossServiceAction',
    width: 720,
    overrides: () async => [
      // Radarr is set up; Sonarr and qBittorrent are not.
      currentSettingsProvider.overrideWith(
        (ref) => settingsWithServices(const [ServiceKey.radarr]),
      ),
      capabilityOverride(const {
        _readWrite: CapabilityGrant.readWrite(),
        _readOnly: CapabilityGrant.readOnly(),
        _unanswered: CapabilityGrant.unanswered(),
      }),
    ],
    scenes: [
      CatalogScene(
        'CrossServiceAction.builder · HeaderActionButton, Radarr set up vs '
        'Sonarr not · glyph and caption drain to 38%, the plate and its 48pt '
        'square stay',
        (_) => _row([
          _labelled('Radarr set up', _openIn(ServiceKey.radarr)),
          _labelled('Sonarr not set up', _openIn(ServiceKey.sonarr)),
        ]),
      ),
      CatalogScene(
        'CrossServiceAction.builder · a TextButton, Radarr set up vs '
        'qBittorrent not · the label dims, the 56 × 44 target does not',
        (_) => _row([
          _labelled('Radarr set up', _openTransfer(ServiceKey.radarr)),
          _labelled(
            'qBittorrent not set up',
            _openTransfer(ServiceKey.qbittorrent),
          ),
        ]),
      ),
      CatalogScene(
        'CrossServiceAction · the default cell around a bare glyph · a 44 × 44 '
        'minimum target in both states',
        (_) => _row([
          _labelled('Radarr set up', _glyphCell(ServiceKey.radarr)),
          _labelled(
            'qBittorrent not set up',
            _glyphCell(ServiceKey.qbittorrent),
          ),
        ]),
      ),
      CatalogScene(
        'CapabilityGatedAction.icon · Unraid VMs, read-write vs read-only key · '
        'the glyph dims inside the IconButton, its target unchanged',
        (_) => _row([
          _labelled('read-write', _vmButton(_readWrite)),
          _labelled('read-only', _vmButton(_readOnly)),
          _labelled('not checked', _vmButton(_unanswered)),
        ]),
      ),
      CatalogScene(
        'CapabilityGatedAction.toggle · TrueNAS share, read-write vs read-only '
        '· the whole switch dims and keeps the server\'s value',
        (_) => _row([
          _labelled('read-write', _toggle(_readWrite)),
          _labelled('read-only', _toggle(_readOnly)),
          _labelled('not checked', _toggle(_unanswered)),
        ]),
      ),
      CatalogScene(
        'CapabilityGatedAction.builder · a FilledButton, admin vs non-admin '
        'account · the label dims, the fill does not',
        (_) => _row([
          _labelled('admin', _save(_readWrite)),
          _labelled('not an admin', _save(_readOnly)),
        ]),
      ),
      CatalogScene(
        'CapabilityGatedMenuLabel · an NPM host menu on a non-admin account · '
        'the write dims, the read beside it stays live, the item stays enabled',
        (_) => _row([
          _labelled('admin', _menu(_readWrite)),
          _labelled('not an admin', _menu(_readOnly)),
        ]),
      ),
      CatalogScene(
        'RoleGatedAction.builder · Manage as a Seerr gate says: the key, an '
        "account of the operator's that may not, and the requester, for whom "
        'it is not drawn at all',
        (_) => _row([
          _labelled('live', _manage(const Live())),
          _labelled(
            'dimmed',
            _manage(const Dimmed("Your account on Seerr can't manage media.")),
          ),
          _labelled('absent', _manage(const Absent())),
        ]),
      ),
      CatalogScene(
        'Text at 200% · a cross-service button, a gated icon, a gated switch, '
        'a gated save and a dimmed Manage: the label grows, the dim stays on '
        'the foreground only, the target never shrinks',
        (_) => _row([
          _labelled('Radarr set up', _openIn(ServiceKey.radarr)),
          _labelled('Sonarr not set up', _openIn(ServiceKey.sonarr)),
          _labelled(
            'qBittorrent not set up',
            _openTransfer(ServiceKey.qbittorrent),
          ),
          _labelled('read-only', _vmButton(_readOnly)),
          _labelled('read-only', _toggle(_readOnly)),
          _labelled('not an admin', _save(_readOnly)),
          _labelled(
            'dimmed',
            _manage(const Dimmed("Your account on Seerr can't manage media.")),
          ),
        ]),
        width: 390,
        textScale: catalogTextScale,
      ),
      _toastScene(
        'Blocked tap at 200% · the sentence takes the lines it needs and the '
            'action moves under it',
        'This Unraid key can\'t start or stop VMs.',
        ServiceKey.unraid.capabilityFixLabel,
        height: 260,
        textScale: catalogTextScale,
      ),
      _toastScene(
        'Blocked tap on a cross-service jump · the caller\'s sentence, one '
            'action to that service\'s settings',
        'Set up qBittorrent to open this transfer.',
        'Settings',
      ),
      _toastScene(
        'Blocked tap on a read-only key · the action is the service\'s own '
            'fix verb',
        'This Unraid key can\'t start or stop VMs.',
        ServiceKey.unraid.capabilityFixLabel,
        height: 140,
      ),
      _toastScene(
        'Blocked tap while the permissions are unknown · re-ask, not replace',
        CapabilityCopy.unansweredToast(ServiceKey.truenas),
        'Check again',
        height: 164,
      ),
    ],
  );
}
