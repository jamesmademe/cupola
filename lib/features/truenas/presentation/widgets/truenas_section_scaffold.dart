import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_version_banner.dart';

/// Standard chrome for a pushed TrueNAS section/detail screen: ambient
/// background, a glass app bar with back navigation, and an optional
/// min-version warning banner above the body.
///
/// A page with writes passes [capabilityAreas] — the TrueNAS capability areas
/// its controls write — and the scaffold draws the capability banner under
/// the version banner, above everything else, whenever the key may not write
/// one of them. Structural rather than per page, so no page can forget it or
/// place it second. Null is a page with no writes, and draws no slot.
class TrueNasSectionScaffold extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final bool showVersionBanner;
  final PreferredSizeWidget? appBarBottom;

  /// The capability areas this page writes. See the class doc.
  final Set<String>? capabilityAreas;

  const TrueNasSectionScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showVersionBanner = true,
    this.appBarBottom,
    this.capabilityAreas,
  });

  @override
  Widget build(BuildContext context) {
    // These section screens are pushed *inside* the app shell, so the floating
    // bottom nav bar overlays them. The body's own scroll view is responsible
    // for reserving bottom space (via
    // `FloatingNavBarMetrics.getScrollViewBottomPadding`) so content scrolls
    // *under* the translucent bar — exactly like the TrueNAS hub. Here we only
    // lift the FAB so it can't be hidden behind the bar.
    return AmbientScaffold(
      accent: ServiceKey.truenas.accent,
      appBar: GlassAppBar(
        title: Text(title),
        actions: actions,
        bottom: appBarBottom,
      ),
      floatingActionButton: floatingActionButton == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(
                bottom: FloatingNavBarMetrics.totalHeight,
              ),
              child: floatingActionButton,
            ),
      body: Column(
        children: [
          if (showVersionBanner) const TrueNasVersionBanner(),
          if (capabilityAreas case final areas?)
            Consumer(
              builder: (context, ref, _) => CapabilityBannerSlot(
                connectionId: capabilityConnectionId(ref, ServiceKey.truenas),
                copy: trueNasCapabilityCopy,
                resources: areas,
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
