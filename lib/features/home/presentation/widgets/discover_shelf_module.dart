/// Discover shelf: one shelf of Discover on the operator's Home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_well.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';

/// Discover shelf, off until the person switches it on: Seerr's trending
/// this week, with the library's state on every poster, the way into
/// Discover at its head. A shelf and not a slab, as Discover draws it.
///
/// Never a count: the shelf is one page of Seerr's. Switched on without
/// Seerr, it asks for Seerr in its place.
class HomeDiscoverShelfModule extends ConsumerWidget {
  const HomeDiscoverShelfModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seerr = ref.watch(
      currentSettingsProvider.select(
        (s) => s.isServiceConfigured(ServiceKey.seerr),
      ),
    );
    // A shelf spans the page (`HomeWell`); the frame that asks for Seerr is
    // a module like the others, in the column.
    if (!seerr) {
      return HomeWell.column(
        context,
        HomeModuleFrame.needsService(
          title: HomeModule.discoverShelf.label,
          service: ServiceKey.seerr,
          headline: 'Set up Seerr to discover movies and series',
          setUpLine: 'Trending, collections, picks from what you watched',
          onSetUp: () => openSettings(
            context,
            ref,
            to: ServiceRoutes.setUp(ServiceKey.seerr),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: DiscoverCarousel(
        title: 'Trending this week',
        sectionId: 'home_shelf',
        inset: HomeWell.shelfInsetOf(context),
        items: ref.watch(atriumTrendingProvider),
        onSeeAll: () => context.go(ServiceRoutes.discover),
        onRetry: () => ref.invalidate(atriumTrendingProvider),
      ),
    );
  }
}
