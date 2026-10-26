import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_choice_row.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

/// What the region **reaches**.
const _regionReachesDescription =
    'Release dates, content ratings and watch providers are all reported for '
    'the region you pick here.';

/// What it does **not** reach: the half that was missing, and the half that
/// matters.
///
/// Only one of the two looks like a filter and neither is: a region that
/// changes the dates on a title looks exactly like a region that changes which
/// titles are listed, so a user who sets this and then sees the same Discover
/// rows concludes the setting is broken. It is not: region is not a parameter
/// on those calls at all.
const _regionDoesNotReachDescription =
    'It does not reach which titles Discover returns: region is not a '
    'parameter on those calls, so the chip on Discover is a label with a '
    'destination, never a filter.';

class SettingsRegionScreen extends ConsumerStatefulWidget {
  const SettingsRegionScreen({super.key});

  @override
  ConsumerState<SettingsRegionScreen> createState() =>
      _SettingsRegionScreenState();
}

class _SettingsRegionScreenState extends ConsumerState<SettingsRegionScreen> {
  final _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final selected = SettingsModel.normalizeRegion(settings.region);
    final theme = Theme.of(context);

    // The current region is pinned above the list: on a thirty-entry picker,
    // finding what is already set should not mean scrolling for it.
    final matches = commonRegions.entries
        .where((entry) => entry.key != selected && _matches(entry))
        .toList(growable: false);

    return AmbientScaffold(
      // No accent: a settings pane has no artwork, so its room is lit by the
      // neutral lamp, the fallback of `AmbientBackground`.
      appBar: const GlassAppBar.inPage(pageTitle: 'Region'),
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            const PageTitle.flush('Region'),
            Text(
              _regionReachesDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _regionDoesNotReachDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _queryController,
              decoration: InputDecoration(
                hintText: 'Search regions',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _queryController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              textInputAction: TextInputAction.search,
              autocorrect: false,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_query.isEmpty) ...[
              SettingsGroupCard.choices(
                children: [
                  SettingsChoiceRow(
                    label: _label(selected),
                    description: 'Current region',
                    selected: true,
                    onSelected: () {},
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (matches.isEmpty)
              AppEmptyState.compact(
                icon: Icons.travel_explore_rounded,
                title: 'No matching region',
                message: 'Try the country name or its two-letter code.',
              )
            else
              SettingsGroupCard.choices(
                children: [
                  for (final entry in matches)
                    SettingsChoiceRow(
                      label: '${entry.value} (${entry.key})',
                      selected: entry.key == selected,
                      onSelected: () => _select(entry.key),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  bool _matches(MapEntry<String, String> entry) {
    if (_query.trim().isEmpty) return true;
    final query = _query.trim().toLowerCase();
    return entry.value.toLowerCase().contains(query) ||
        entry.key.toLowerCase().contains(query);
  }

  String _label(String code) {
    final name = commonRegions[code] ?? code;
    return '$name ($code)';
  }

  Future<void> _select(String code) async {
    await ref
        .read(settingsProvider.notifier)
        .update((current) => current.copyWith(region: code));
  }
}
