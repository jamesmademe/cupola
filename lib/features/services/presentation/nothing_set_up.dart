import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The whole page while no service is set up: the ring at rest and the way
/// in. The Home and Stack both show it, and nothing else, until there is a
/// first connection.
///
/// The page owns the viewport, not the empty state: see the contract on
/// `AppEmptyState`. Its height is entirely text, and at an accessibility
/// reading size a 72pt icon well, a wrapped title, a two-line message and a
/// button clear a short phone, taking the only button on the screen with
/// them. The `minHeight` keeps it centred while it fits, so nothing moves at
/// the default reading size.
///
/// Default physics deliberately: there is no `RefreshIndicator` here, because
/// with nothing configured there is nothing to re-fetch: the page rebuilds
/// off settings.
class NothingSetUpView extends StatelessWidget {
  const NothingSetUpView({super.key, required this.bottomPadding});

  /// The floating bar's clearance. The bar floats *over* the page, so
  /// centring in the full viewport puts the optical centre behind it and the
  /// block reads low; reserving the clearance inside the centring box lifts it
  /// back onto the visible middle.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomPadding),
            // Not a `Set up X`: nothing is chosen yet, so the way in is the
            // list every service's setup form hangs off.
            child: _NothingSetUp(
              onSetUpServices: () =>
                  context.go(ServiceRoutes.settingsConnections),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring at rest, and the claim it makes.
///
/// This is the same object onboarding opens with, which is what makes "Skip for
/// now" cost nothing: the promise persists as the empty state instead of
/// evaporating into a grey placeholder. The button opens Connections, where each
/// service is set up on its own form, so it says "Set up a service", not the
/// pick step's "Pick your services", which would promise the several-at-once
/// choice it does not lead back to. Deliberately *not* `AppEmptyState`: that
/// widget is for a region that came up empty, and this page is the product's
/// front door on a first run.
class _NothingSetUp extends StatelessWidget {
  const _NothingSetUp({required this.onSetUpServices});
  final VoidCallback onSetUpServices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ServiceRing(
            states: const {},
            diameter: serviceRingDiameter(context, preferred: 268),
            spin: true,
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
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${ServiceKey.values.length} services are waiting for an address. '
            'Light one up and this screen fills in.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: onSetUpServices,
            child: const Text('Set up a service'),
          ),
        ],
      ),
    );
  }
}
