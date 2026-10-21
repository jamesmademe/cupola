import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/widgets/service_ring.dart';

/// Covers the app while the OS is taking its app-switcher image.
///
/// iOS and macOS have no `FLAG_SECURE`; the switcher snapshot is taken when the
/// app stops being active, which is exactly when this cover is shown. On a
/// desktop the window losing focus is normal and covering it would be wrong, so
/// the cover is mobile-only; Android additionally gets the real flag from
/// [SecureScreen].
class AppSnapshotCover extends StatefulWidget {
  const AppSnapshotCover({super.key, required this.child});

  final Widget child;

  @override
  State<AppSnapshotCover> createState() => _AppSnapshotCoverState();
}

class _AppSnapshotCoverState extends State<AppSnapshotCover>
    with WidgetsBindingObserver {
  bool _covered = false;

  static bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

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
    if (!_isMobile) return;
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
