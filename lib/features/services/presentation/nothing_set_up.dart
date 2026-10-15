import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/widgets/setup_doors.dart';

/// The whole page while no service is set up: the ring at rest and the way
/// in. The Home, Activity and the Stack show it, and nothing else, until there
/// is a first connection.
///
/// The page owns the viewport, not the empty state: see the contract on
/// `AppEmptyState`. Its height is entirely text, and at an accessibility
/// reading size the ring, a wrapped title and the door clear a short phone,
/// taking the only button on the screen with them. The `minHeight` keeps it
/// centred while it fits, so nothing moves at the default reading size.
///
/// Default physics deliberately: there is no `RefreshIndicator` here, because
/// with nothing configured there is nothing to re-fetch: the page rebuilds
/// off settings.
class NothingSetUpView extends StatelessWidget {
  const NothingSetUpView({super.key, required this.bottomPadding, this.header});

  /// The floating bar's clearance. The bar floats *over* the page, so
  /// centring in the full viewport puts the optical centre behind it and the
  /// block reads low; reserving the clearance inside the centring box lifts it
  /// back onto the visible middle.
  final double bottomPadding;

  /// What the page keeps above the ring: the Home's date. With one, the ring
  /// sits under it rather than in the middle of the screen.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final body = _NothingSetUp(
      onSetUp: () => context.push(ServiceRoutes.welcomeConnect),
      onSignIn: () => context.push(ServiceRoutes.welcomeSignIn),
    );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            child: switch (header) {
              final header? => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, body],
              ),
              null => Center(child: body),
            },
          ),
        ),
      ),
    );
  }
}

/// The ring at rest, and the way in.
///
/// The same ring the Welcome opens with, still now: nothing is set up, so
/// nothing in it moves. The door is the Welcome's own ([SetupDoors]), and
/// opens Connect directly, since the claim has already been made. Deliberately
/// *not* `AppEmptyState`: that widget is for a region that came up empty, and
/// this page is the product's front door until something answers.
class _NothingSetUp extends StatelessWidget {
  const _NothingSetUp({required this.onSetUp, required this.onSignIn});
  final VoidCallback onSetUp;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ServiceRing(
              states: const {},
              diameter: serviceRingDiameter(context, preferred: 252),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            // Not "Nothing answers": that is the word for a service that was
            // asked and stayed silent, and here nothing has been asked yet.
            'Nothing is set up yet.',
            style: theme.textTheme.titleLarge!
                .weight(FontWeight.w600)
                .copyWith(color: scheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          SetupDoors(onSetUp: onSetUp, onSignIn: onSignIn),
        ],
      ),
    );
  }
}
