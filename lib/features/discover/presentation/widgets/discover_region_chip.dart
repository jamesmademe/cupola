import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// Where the gear lands. The same literal the four settings call sites use;
/// there is no route constant for the settings tree yet.
const String _regionSettingsLocation = '/settings/region';

/// "Region · IT" — a **readout** of Settings › Region with a door to it.
///
/// Decision 32, and the whole point of the widget is what it refuses to be. A
/// picker here would change nothing: region is not a parameter on any
/// `/api/v1/discover/*` call, so no choice made on this page could alter which
/// titles the rails return. What the setting does reach is one level down — a
/// title's release dates, its certification and where it can be watched, all of
/// which `discover_detail_screen.dart` reads through `regionProvider`.
///
/// So this is a label, not a control over the list, and it has to *look* like
/// one: no selected-state fill, no chevron-down, and deliberately not
/// [AppRadius.pill], which the token reserves for selected affordances. A
/// region chip that looks like a filter and filters nothing is a setting the
/// user concludes is broken — that failure is why decision 32 was asked at all.
///
/// It is still one button: the whole plate opens app settings, and it keeps the
/// 48dp target even though the visible plate is smaller, so it is reachable by
/// touch and by a screen reader with a name that says both where it is and
/// where it goes.
class DiscoverRegionChip extends ConsumerWidget {
  const DiscoverRegionChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Watched rather than read: the label is the live value of the setting, so
    // changing the region in Settings and coming back shows the new one without
    // the page being rebuilt for any other reason. Nothing is re-fetched — see
    // the class comment for why there is nothing to re-fetch.
    final code = SettingsModel.normalizeRegion(ref.watch(regionProvider));

    // The plate shows the code (the board's "Region · IT" and the only form
    // that fits a chip); the screen reader gets the country, because "IT" is
    // read out as a two-letter initialism and is not a name.
    final spokenRegion = commonRegions[code] ?? code;

    return Semantics(
      container: true,
      button: true,
      label: 'Region, $spokenRegion',
      hint: 'Opens app settings to change the region',
      onTap: () => context.push(_regionSettingsLocation),
      child: InkWell(
        onTap: () => context.push(_regionSettingsLocation),
        borderRadius: AppRadius.borderRadiusSm,
        // The name and the tap action are published above; without this the ink
        // response adds a second, unnamed actionable node.
        excludeFromSemantics: true,
        child: ConstrainedBox(
          // 48, the row contract: the plate is ~30 tall and must not shrink the
          // target to match it.
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Center(
            widthFactor: 1,
            // The plate is what the eye reads; the node above is what the
            // screen reader reads. Without this exclusion the code comes along
            // too and the label becomes "Region, Italy / Region · IT" — the
            // initialism this widget spells out for exactly that reason.
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: AppRadius.borderRadiusSm,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.public_rounded,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Region · $code',
                      style: theme.textTheme.labelMedium!
                          .weight(FontWeight.w600)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // The gear is the door, drawn inside the one target rather
                    // than beside it as a second button: two tap targets in one
                    // chip, one of them the whole chip, is an ambiguity a screen
                    // reader user would have to resolve by guessing.
                    Icon(
                      Icons.settings_rounded,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
