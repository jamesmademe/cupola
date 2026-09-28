@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_dialog.dart';

import 'catalog.dart';

/// Opens the real dialog on a navigator of the scene's own, so the route —
/// barrier and all — paints inside the scene rather than above the sheet.
class _Opened extends StatefulWidget {
  const _Opened(this.open);

  final Future<AppConfirmResult> Function(BuildContext context) open;

  @override
  State<_Opened> createState() => _OpenedState();
}

class _OpenedState extends State<_Opened> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface);
}

CatalogScene _scene(
  String caption,
  Future<AppConfirmResult> Function(BuildContext context) open, {
  double height = 320,
  double width = 390,
  CatalogPlatform platform = CatalogPlatform.phone,
}) => CatalogScene(
  caption,
  (_) => ClipRect(
    child: Navigator(
      onGenerateRoute: (_) =>
          PageRouteBuilder<void>(pageBuilder: (_, _, _) => _Opened(open)),
    ),
  ),
  width: width,
  height: height,
  platform: platform,
);

Future<AppConfirmResult> _grab(BuildContext context) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Grab release',
  message: 'Download "Nosferatu.1922.1080p.BluRay.x264"?',
  confirmLabel: 'Download',
);

Future<AppConfirmResult> _remove(
  BuildContext context, {
  bool deleteChecked = true,
}) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Remove from queue?',
  message: 'Metropolis.1927.1080p.BluRay.x264',
  icon: Icons.delete_outline_rounded,
  confirmLabel: 'Remove',
  destructive: true,
  options: [
    AppConfirmOption(
      key: 'removeFromClient',
      label: 'Delete from download client',
      subtitle: 'Also removes the files that have been downloaded so far.',
      initialValue: deleteChecked,
      danger: true,
    ),
    const AppConfirmOption(
      key: 'blocklist',
      label: 'Blocklist this release',
      subtitle: 'Stops it being grabbed again, so a search finds another.',
    ),
  ],
);

Future<AppConfirmResult> _deleteSnapshot(BuildContext context) =>
    showAppConfirmDialog(
      context: context,
      useRootNavigator: false,
      title: 'Delete snapshot?',
      message: 'tank/media@auto-2026-09-22_00-00',
      confirmLabel: 'Delete',
      destructive: true,
    );

Future<AppConfirmResult> _approve(BuildContext context) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Approve this request?',
  message:
      'Sherlock Jr. goes to the service that handles it and starts '
      'downloading.',
  icon: Icons.check_circle_outline_rounded,
  confirmLabel: 'Approve',
);

Future<AppConfirmResult> _longTitle(BuildContext context) =>
    showAppConfirmDialog(
      context: context,
      useRootNavigator: false,
      title:
          'Delete The Cabinet of Dr. Caligari and every file Radarr holds '
          'for it?',
      message: 'The Cabinet of Dr. Caligari (1920)',
      confirmLabel: 'Delete',
      destructive: true,
      dangerNote: 'The files go too. Radarr can download them again later.',
    );

void main() {
  catalogCard(
    'AppDialog',
    width: 880,
    scenes: [
      _scene(
        'Standard · the grab confirmation · Cancel as a TextButton, the '
        'confirm as a primary FilledButton',
        _grab,
        height: 300,
      ),
      _scene(
        'Standard with an icon · Approve this request? · the icon in onSurface',
        _approve,
        height: 320,
      ),
      _scene(
        'destructive, a danger option checked · the option and the note turn '
        'red, each walked against the dialog',
        _remove,
        height: 560,
      ),
      _scene(
        'destructive, the danger option unchecked · no note until it is '
        'checked; the confirm stays red',
        (context) => _remove(context, deleteChecked: false),
        height: 500,
      ),
      _scene(
        'destructive, no options · the default icon and the danger note always '
        'show',
        _deleteSnapshot,
        height: 360,
      ),
      _scene(
        'Long title and a custom dangerNote · the title stops at two lines',
        _longTitle,
        height: 380,
      ),
      _scene(
        'On a desktop window · the same dialog under compact density',
        _remove,
        width: 832,
        height: 480,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
