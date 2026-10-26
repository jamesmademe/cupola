import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_choice_row.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

class SettingsAppearanceScreen extends ConsumerWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);

    return AmbientScaffold(
      // No accent: a settings pane has no artwork, so its room is lit by the
      // neutral lamp, the fallback of `AmbientBackground`.
      appBar: const GlassAppBar.inPage(pageTitle: 'Appearance'),
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          // No lead-in: the three choices say what they do, and the one this
          // page had promised a color for each service, which the app never
          // paints (color is information, and a service accent is not).
          children: [
            const PageTitle.flush('Appearance'),
            SettingsGroupCard.choices(
              children: [
                for (final mode in AppThemeMode.values)
                  SettingsChoiceRow(
                    label: mode.label,
                    description: _describe(mode),
                    selected: settings.themeMode == mode,
                    onSelected: () => _updateThemeMode(ref, settings, mode),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _describe(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => 'Follows your device setting',
      AppThemeMode.light => 'Always light',
      AppThemeMode.dark => 'Always dark',
    };
  }

  Future<void> _updateThemeMode(
    WidgetRef ref,
    SettingsModel settings,
    AppThemeMode value,
  ) async {
    if (value == settings.themeMode) return;

    await ref
        .read(settingsProvider.notifier)
        .update(
          (current) => current.themeMode == value
              ? current
              : current.copyWith(themeMode: value),
        );
  }
}
