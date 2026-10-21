import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/service_ring.dart';

/// Covers the app while iOS is taking its app-switcher image.
///
/// iOS has no `FLAG_SECURE`; the switcher snapshot is taken when the app stops
/// being active, which is exactly when this cover is shown. Android does not
/// need it: [SecureScreen] sets the platform flag on every screen that shows a
/// credential or a pairing code, and the flag blanks the Recents snapshot by
/// itself. A desktop window losing focus is normal and covering it would be
/// wrong.
class AppSnapshotCover extends StatefulWidget {
  const AppSnapshotCover({super.key, required this.child});

  final Widget child;

  @override
  State<AppSnapshotCover> createState() => _AppSnapshotCoverState();
}

class _AppSnapshotCoverState extends State<AppSnapshotCover>
    with WidgetsBindingObserver {
  bool _covered = false;

  /// iOS alone: Android's half is the real flag, set per screen by
  /// [SecureScreen].
  static bool get _covers => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_covers) return;
    final covered = state != AppLifecycleState.resumed;
    if (covered != _covered && mounted) {
      setState(() => _covered = covered);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_covered) const Positioned.fill(child: _SnapshotCover()),
      ],
    );
  }
}

class _SnapshotCover extends StatelessWidget {
  const _SnapshotCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(child: CupolaMark.sized(72)),
    );
  }
}
