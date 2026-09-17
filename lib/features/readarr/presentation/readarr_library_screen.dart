import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/readarr/presentation/widgets/readarr_tiles.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Readarr's Library tab: the full author list.
///
/// It was a page pushed from the dashboard's "Authors" section and is now the
/// root of a branch, at the same path it always had. Two things follow from
/// that and both are why this class grew parameters.
class ReadarrLibraryScreen extends ConsumerWidget {
  /// Whether to draw this screen's own app bar.
  ///
  /// False inside the tab shell, where `ServiceHomeScreen` draws the service
  /// band and `ServiceTabScaffold` the tab bar above it: a third bar of its own
  /// would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  const ReadarrLibraryScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The configured check comes first, as it does on every other service's
    // landing surface: `readarrServiceProvider` throws for a Readarr that was
    // never set up, so without this the tab would answer a question about an
    // unreachable server with "Failed to load authors" — an error about a
    // request that was never worth making.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.readarr),
      ),
    );
    if (!configured) {
      return AmbientScaffold(
        accent: AppColors.readarr,
        appBar: showAppBar ? const GlassAppBar(title: Text('Authors')) : null,
        // `.forService`, never the generic form: the door goes to Readarr's own
        // connection form rather than to the settings index.
        body: SafeArea(
          child: NotConfiguredPlaceholder.forService(ServiceKey.readarr),
        ),
      );
    }

    final authorsAsync = ref.watch(readarrAuthorsProvider);

    return AmbientScaffold(
      accent: AppColors.readarr,
      appBar: showAppBar ? const GlassAppBar(title: Text('Authors')) : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(readarrAuthorsProvider);
            // The rail's own non-swallowing read. See `movies_screen.dart`.
            ref.invalidate(readarrKpiLibraryProvider);
            await Future<void>.delayed(AppAnimation.durationMd);
          },
          child: authorsAsync.when(
            data: (authors) {
              if (authors.isEmpty) {
                return const _EmptyLibrary();
              }
              final sorted = [...authors]
                ..sort(
                  (a, b) => a.authorName.toLowerCase().compareTo(
                    b.authorName.toLowerCase(),
                  ),
                );
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: topPadding + AppSpacing.sm,
                  bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(
                    context,
                  ),
                ),
                itemCount: sorted.length,
                itemBuilder: (context, index) =>
                    ReadarrAuthorTile(author: sorted[index]),
              );
            },
            loading: () => const ListRowsShimmer(count: 8),
            error: (error, _) => InlineErrorRetry(
              message: 'Failed to load authors',
              onRetry: () => ref.invalidate(readarrAuthorsProvider),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(child: Text('No authors in the library yet.')),
      ],
    );
  }
}
